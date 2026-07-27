import BlockInputKit
import Foundation
import Observation

/// Backs the Agents settings `AGENTS.md` sub-section: owns the shared-file draft,
/// per-agent link states, and the BlockInputKit document store the editor renders.
///
/// Observation shape is deliberate: the document store and dirty baseline are
/// `@ObservationIgnored` so keystrokes do not re-render the hosting view, which
/// would re-run `BlockInputView.configure(_:)` on every edit. Only coarse state
/// (`isDirty`, `linkStates`, load/error state) is observed.
@MainActor
@Observable
final class GlobalInstructionsEditorModel {
    @ObservationIgnored private let service: GlobalAgentInstructionsService
    @ObservationIgnored private let agentRegistry: AgentRegistry
    @ObservationIgnored let documentStore = BlockInputMemoryDocumentStore()
    /// Stable undo controller so reconfiguration on coarse state changes does not drop the undo stack.
    @ObservationIgnored let undoController = BlockInputUndoController()
    @ObservationIgnored private var hasLoaded = false

    private(set) var isDirty = false
    private(set) var isLoading = false
    private(set) var linkStates: [String: AgentInstructionsLinkState] = [:]
    /// Bumped whenever disk content replaces the document store. The editor host
    /// reads it in `body` so the async load invalidates it directly — SwiftUI
    /// otherwise skips the host's body because its only stored property is a
    /// reference whose pointer never changes, leaving the editor pre-load empty.
    private(set) var contentGeneration = 0
    var errorMessage: String?

    init(service: GlobalAgentInstructionsService, agentRegistry: AgentRegistry) {
        self.service = service
        self.agentRegistry = agentRegistry
    }

    var sharedPathDescription: String {
        service.sharedPathDescription
    }

    /// Agents with an instructions path, in registry order, paired with their link state.
    var linkRows: [(agent: AgentDefinition, state: AgentInstructionsLinkState)] {
        agentRegistry.agents.compactMap { agent in
            guard let state = linkStates[agent.id] else {
                return nil
            }
            return (agent: agent, state: state)
        }
    }

    /// Idempotent first load; revisiting the tab must not clobber an unsaved draft.
    func loadIfNeeded() async {
        guard !hasLoaded else {
            await refreshLinkStates()
            return
        }
        hasLoaded = true
        await reloadFromDisk()
    }

    func save() async {
        do {
            try await service.saveShared(documentStore.document.markdown)
            setDirty(false)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Discards the draft and reloads the shared file from disk.
    func revert() async {
        await reloadFromDisk()
    }

    func copyIntoShared(agentID: String) async {
        do {
            try await service.copyIntoShared(agentID: agentID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        // The shared file changed underneath the editor; an unsaved draft would
        // silently drop the migrated content on the next save, so reload.
        await reloadFromDisk()
    }

    func link(agentID: String, copyingContents: Bool) async {
        do {
            try await service.link(agentID: agentID, copyingContents: copyingContents)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        await reloadFromDisk()
    }

    /// Called from the editor configuration's `onDocumentChange`.
    func noteDocumentChanged() {
        setDirty(true)
    }
}

private extension GlobalInstructionsEditorModel {
    func reloadFromDisk() async {
        isLoading = true
        defer {
            isLoading = false
        }
        do {
            let markdown = try await service.loadShared()
            documentStore.replaceDocument(BlockInputDocument(markdown: markdown))
            contentGeneration += 1
            setDirty(false)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshLinkStates()
    }

    func refreshLinkStates() async {
        let states = await service.linkStates()
        if linkStates != states {
            linkStates = states
        }
    }

    /// `@Observable` notifies on every set, equal value or not; the guard keeps
    /// per-keystroke dirty notes from re-rendering the host.
    func setDirty(_ newValue: Bool) {
        if isDirty != newValue {
            isDirty = newValue
        }
    }
}

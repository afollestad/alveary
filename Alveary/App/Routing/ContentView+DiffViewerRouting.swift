import Foundation
import SwiftData

/// Root selection reduced to the identity the Diff Viewer actually routes on.
///
/// Built from selection tokens only — no SwiftData property reads — so the
/// click-to-highlight frame never waits on a fetch. `Settings` normalizes to the
/// same route as its preserved bookmark, so opening Settings from a project does
/// not re-route the pane.
enum DiffViewerRoutingSelection: Equatable {
    case none
    case thread(PersistentIdentifier)
    case project(PersistentIdentifier)

    init(selection: SidebarItem?, previousSelection: AppState.SidebarBookmark?) {
        switch selection {
        case .thread(let thread):
            self = .thread(thread.persistentModelID)
        case .project(let project):
            self = .project(project.persistentModelID)
        case .settings:
            switch previousSelection {
            case .threadId(let threadID):
                self = .thread(threadID)
            case .projectID(let id):
                self = .project(id)
            case .skills, .mcp, .scheduled, .pullRequests, .archived, nil:
                self = .none
            }
        case .skills, .mcp, .scheduled, .pullRequests, .archived, nil:
            self = .none
        }
    }
}

/// The complete set of inputs that decide what the Diff Viewer shows.
struct DiffViewerRoutingKey: Equatable {
    let selection: DiffViewerRoutingSelection
    let scope: DiffViewerSwitchScope
    let draftRevision: UInt64
    var folderRevision: UInt64 = 0
}

/// Runs one Diff Viewer route with an injected suspension gate.
///
/// The gate is `Task.yield()` in production; tests replace it to prove that target
/// resolution and pane work start only after the selected frame has painted, and
/// that a superseded key applies nothing.
@MainActor
struct DiffViewerRouteRunner {
    let isCurrent: @MainActor (DiffViewerRoutingKey) -> Bool
    let resolveTarget: @MainActor (DiffViewerRoutingSelection) -> DiffViewerSwitchTarget?
    let clear: @MainActor () -> Void
    let applyTarget: @MainActor (DiffViewerSwitchTarget, DiffViewerSwitchScope) async -> Void
    let suspendBeforeResolving: @MainActor () async -> Void
    var prepareTarget: @MainActor (DiffViewerSwitchTarget) async throws -> DiffViewerSwitchTarget = { $0 }
    var presentError: @MainActor (String) -> Void = { _ in }

    func run(key: DiffViewerRoutingKey) async {
        await suspendBeforeResolving()
        guard isCurrent(key) else {
            return
        }

        let target = resolveTarget(key.selection)

        guard isCurrent(key) else {
            return
        }

        guard let target else {
            clear()
            return
        }

        do {
            let preparedTarget = try await prepareTarget(target)
            guard isCurrent(key) else { return }
            await applyTarget(preparedTarget, key.scope)
        } catch {
            guard isCurrent(key) else { return }
            clear()
            presentError(error.localizedDescription)
        }
    }
}

extension ContentView {
    var diffViewerRoutingSelection: DiffViewerRoutingSelection {
        DiffViewerRoutingSelection(
            selection: appState.selectedSidebarItem,
            previousSelection: appState.previousSelection
        )
    }

    var diffViewerSwitchScope: DiffViewerSwitchScope {
        // The toolbar diff summary must stay fresh even while the pane is
        // hidden; only the heavy pane payload waits for the pane to show.
        isDiffViewerRendered ? .full : .toolbarStatsOnly
    }

    var diffViewerRoutingKey: DiffViewerRoutingKey {
        DiffViewerRoutingKey(
            selection: diffViewerRoutingSelection,
            scope: diffViewerSwitchScope,
            draftRevision: diffViewerDraftRefreshRevision,
            folderRevision: folderSelection.revision
        )
    }

    func routeDiffViewer(key: DiffViewerRoutingKey) async {
        await DiffViewerRouteRunner(
            isCurrent: isDiffViewerRoutingKeyCurrent,
            resolveTarget: resolvedDiffViewerTarget(for:),
            clear: { diffViewModel.clear() },
            applyTarget: { target, scope in
                await diffViewModel.switchToTarget(target, scope: scope)
            },
            // Let the new selection paint before any SwiftData or Git work starts.
            suspendBeforeResolving: { await Task.yield() },
            prepareTarget: { try await $0.resolvingRepositoryDirectory(using: diffViewModel.gitService) },
            presentError: { diffViewModel.presentGitError($0) }
        ).run(key: key)
    }

    /// `Task.isCancelled` covers the draft revision, which only ever changes by
    /// restarting the keyed task; selection and scope are read live from
    /// reference-backed state so a resumed job cannot act on a stale route.
    func isDiffViewerRoutingKeyCurrent(_ key: DiffViewerRoutingKey) -> Bool {
        guard !Task.isCancelled else {
            return false
        }
        return key.selection == diffViewerRoutingSelection && key.scope == diffViewerSwitchScope
            && key.folderRevision == folderSelection.revision
    }

    func resolvedDiffViewerTarget(for selection: DiffViewerRoutingSelection) -> DiffViewerSwitchTarget? {
        switch selection {
        case .none:
            return nil
        case .thread(let threadID):
            guard let thread = uiModelContext.resolveThread(id: threadID),
                  thread.archivedAt == nil else {
                return nil
            }
            guard let folder = folderSelection.selected(
                in: thread.workspaceFolderTargets, owner: .thread(threadID)
            ) else { return nil }
            return DiffViewerSwitchTarget.forFolder(
                folder, conversationIDs: liveDiffViewerConversationIDs(for: thread)
            )
        case .project(let id):
            guard let project = uiModelContext.resolveProject(id: id) else {
                return nil
            }
            return diffViewerTarget(for: project)
        }
    }

    private func diffViewerTarget(for project: Project) -> DiffViewerSwitchTarget? {
        guard let folder = folderSelection.selected(
            in: project.workspaceFolderTargets, owner: .project(project.id)
        ) else { return nil }
        return DiffViewerSwitchTarget.forFolder(
            folder, conversationIDs: Self.projectDiffViewerConversationIDs(in: folder.directory, modelContext: uiModelContext)
        )
    }

    /// A folder can be shared by threads in other projects; archived and draft threads contribute no conversations.
    static func projectDiffViewerConversationIDs(in directory: String, modelContext: ModelContext) -> Set<String> {
        var descriptor = FetchDescriptor<AgentThread>(
            predicate: #Predicate { thread in
                thread.archivedAt == nil && thread.isDraft == false
            }
        )
        // The project route reads every candidate thread's conversations right after this
        // fetch, so prefetching keeps that batched instead of one fault per thread.
        descriptor.relationshipKeyPathsForPrefetching = [\.conversations]
        let threads = ((try? modelContext.fetch(descriptor)) ?? []).filter {
            $0.workspaceFolderTargets.contains { $0.directory == directory }
        }
        return Set(threads.flatMap { $0.conversations.map(\.id) })
    }

    private func liveDiffViewerConversationIDs(for thread: AgentThread) -> Set<String> {
        let threadID = thread.persistentModelID
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { conversation in
                conversation.thread?.persistentModelID == threadID
            }
        )
        return Set(((try? uiModelContext.fetch(descriptor)) ?? []).map(\.id))
    }

}

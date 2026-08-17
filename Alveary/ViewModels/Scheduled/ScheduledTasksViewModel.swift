import AgentCLIKit
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ScheduledTasksViewModel {
    @ObservationIgnored let modelContext: ModelContext
    @ObservationIgnored let mutationService: ScheduledTaskMutationService
    @ObservationIgnored let providerDiscovery: (any AgentCLIKit.AgentProviderDiscoveryService)?
    @ObservationIgnored let settingsService: any SettingsService
    @ObservationIgnored let agentRegistry: AgentRegistry
    @ObservationIgnored let runNowAction: @MainActor (ScheduledTaskRunNowRequest) -> Bool
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored let currentTimeZone: () -> TimeZone
    @ObservationIgnored let notificationCenter: NotificationCenter
    @ObservationIgnored var changeObservationTask: Task<Void, Never>?
    @ObservationIgnored var threadObservationTask: Task<Void, Never>?
    @ObservationIgnored var proposalObservationTask: Task<Void, Never>?
    @ObservationIgnored var sectionObservationTask: Task<Void, Never>?

    /// Where the grid was scrolled to, so leaving the screen and coming back lands there; see
    /// ``ScrollOffsetStore`` for why it cannot live on the screen.
    @ObservationIgnored let listScrollOffset = ScrollOffsetStore()

    private(set) var tasks: [ScheduledTaskRowPresentation] = []
    private(set) var projects: [ScheduledTaskProjectOption] = []
    private(set) var existingThreadTargets: [ScheduledTaskThreadOption] = []
    private(set) var sectionOptions: [ScheduledTaskSectionOption] = []
    var providerStatuses: [String: AgentCLIKit.AgentProviderStatus] = [:]
    var providerOrdering: [String] = []
    var isLoadingProviders = false
    var pendingRunNowDefinitionIDs = Set<String>()
    private(set) var activePaneTarget: ScheduledTaskPaneTarget?
    /// Thread that opened the active pane from its transcript; `nil` for screen-opened panes.
    var proposalPaneOriginThreadID: PersistentIdentifier?
    private(set) var paneSessions: [ScheduledTaskPaneTarget: ScheduledTaskPaneSession] = [:]
    private(set) var pendingPaneDismissals: Set<PaneSessionDismissalRequest<ScheduledTaskPaneTarget>> = []
    private(set) var paneDismissalGeneration = 0
    private(set) var paneFocusRestorationID = ScheduledTaskPaneTarget.create.defaultFocusRestorationID
    private var deactivatedPaneDismissals: Set<PaneSessionDismissalRequest<ScheduledTaskPaneTarget>> = []
    var errorMessage: String?
    /// The active tab; restored from settings and persisted through `selectFilter(_:)`.
    private(set) var selectedFilter = ScheduledTasksFilter.all

    init(
        modelContext: ModelContext,
        mutationService: ScheduledTaskMutationService,
        providerDiscovery: (any AgentCLIKit.AgentProviderDiscoveryService)? = nil,
        settingsService: any SettingsService,
        agentRegistry: AgentRegistry = DefaultAgentRegistry(),
        notificationCenter: NotificationCenter = .default,
        runNow: @escaping @MainActor (ScheduledTaskRunNowRequest) -> Bool,
        now: @escaping () -> Date = Date.init,
        currentTimeZone: @escaping () -> TimeZone = { .autoupdatingCurrent }
    ) {
        self.modelContext = modelContext
        self.mutationService = mutationService
        self.providerDiscovery = providerDiscovery
        self.settingsService = settingsService
        self.agentRegistry = agentRegistry
        self.notificationCenter = notificationCenter
        runNowAction = runNow
        self.now = now
        self.currentTimeZone = currentTimeZone
        selectedFilter = ScheduledTasksFilter(rawValue: settingsService.current.scheduledTasksSelectedTab) ?? .all

        reload()
        observeChanges()
    }

    /// Switches the visible tab and persists it as the next launch's initial tab.
    func selectFilter(_ filter: ScheduledTasksFilter) {
        guard selectedFilter != filter else {
            return
        }
        selectedFilter = filter
        settingsService.update { $0.scheduledTasksSelectedTab = filter.rawValue }
    }

    deinit {
        changeObservationTask?.cancel()
        threadObservationTask?.cancel()
        proposalObservationTask?.cancel()
        sectionObservationTask?.cancel()
    }

    func load() async {
        await refreshProviders()
        reload()
    }

    func reload() {
        do {
            let definitions = try modelContext.fetch(
                FetchDescriptor<ScheduledTask>(
                    sortBy: [SortDescriptor(\ScheduledTask.modifiedAt, order: .reverse)]
                )
            )
            tasks = definitions.map(makeRowPresentation)

            let fetchedProjects = try modelContext.fetch(
                FetchDescriptor<Project>(
                    sortBy: [SortDescriptor(\Project.name), SortDescriptor(\Project.path)]
                )
            )
            projects = fetchedProjects.map { ScheduledTaskProjectOption(path: $0.path, name: $0.name) }
            existingThreadTargets = try makeExistingThreadOptions()
            sectionOptions = try makeSectionOptions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func tasks(for filter: ScheduledTasksFilter) -> [ScheduledTaskRowPresentation] {
        switch filter {
        case .all:
            tasks
        case .active:
            tasks.filter { $0.state == .active }
        case .paused:
            tasks.filter { $0.state == .paused }
        }
    }

    func requestCreate(focusRestorationID: String? = nil) {
        openCreatePane(replacementDraft: nil, focusRestorationID: focusRestorationID)
    }

    /// Opens the create pane seeded from an empty-state suggestion.
    ///
    /// The draft is a replacement rather than a fallback: picking a suggestion is an
    /// explicit choice of starting point, so a session cached from an earlier one must not
    /// survive it. Dismiss the pull-request suggestion, pick the digest, and reusing the
    /// cached draft would reopen the pull-request prompt under the new card's name.
    func requestCreate(from suggestion: ScheduledTaskSuggestion, focusRestorationID: String? = nil) {
        openCreatePane(
            replacementDraft: makeSuggestionDraft(suggestion),
            focusRestorationID: focusRestorationID
        )
    }

    /// The one entry point for the create pane, so its dismissal bookkeeping cannot drift
    /// between the blank and pre-filled routes.
    ///
    /// A `nil` `replacementDraft` reuses whatever session is cached, which is what keeps a
    /// dismissed blank draft's typing alive across a reopen; passing one discards it.
    private func openCreatePane(
        replacementDraft: ScheduledTaskEditorDraft?,
        focusRestorationID: String?
    ) {
        proposalPaneOriginThreadID = nil
        paneFocusRestorationID = focusRestorationID ?? ScheduledTaskPaneTarget.create.defaultFocusRestorationID
        errorMessage = nil
        discardCompletedSessionIfNeeded(for: .create)
        if let replacementDraft {
            paneSessions[.create] = ScheduledTaskPaneSession(
                generation: UUID(),
                draft: replacementDraft
            )
        } else if paneSessions[.create] == nil {
            paneSessions[.create] = ScheduledTaskPaneSession(
                generation: UUID(),
                draft: makeNewDraft()
            )
        }
        if let generation = paneSessions[.create]?.generation {
            deactivatedPaneDismissals.remove(.init(target: .create, generation: generation))
        }
        activePaneTarget = .create
    }

    /// Opens the editor pane for a definition, reporting whether it could. A durable entry
    /// point — a transcript card, a notification — names a task that may have been deleted
    /// since, so it needs the answer to route elsewhere instead of doing nothing.
    @discardableResult
    func requestEdit(definitionID: String, focusRestorationID: String? = nil) -> Bool {
        let target = ScheduledTaskPaneTarget.edit(definitionID)
        // Build the draft before reusing a cached session: the session can outlive its
        // definition when the delete happened elsewhere, and the builder is what reports
        // the vanished row and drops it from the list.
        guard let draft = makeEditDraft(definitionID: definitionID) else {
            discardEditSession(definitionID: definitionID)
            return false
        }
        // Screen-opened edits are unscoped; the transcript entry point re-stamps origin.
        proposalPaneOriginThreadID = nil
        discardCompletedSessionIfNeeded(for: target)
        if paneSessions[target] == nil {
            paneSessions[target] = ScheduledTaskPaneSession(generation: UUID(), draft: draft)
        }
        if let generation = paneSessions[target]?.generation {
            deactivatedPaneDismissals.remove(.init(target: target, generation: generation))
        }
        paneFocusRestorationID = focusRestorationID ?? target.defaultFocusRestorationID
        errorMessage = nil
        activePaneTarget = target
        return true
    }

    /// Opens the proposal in the shared editor pane so a scheduling proposal is reviewed
    /// with the same controls and section set as the Scheduled screen.
    func requestProposalReview(
        _ presentation: ScheduledTaskProposalPresentation,
        originThreadID: PersistentIdentifier?
    ) {
        guard let definitionDraft = presentation.definitionDraft else {
            return
        }
        let target = ScheduledTaskPaneTarget.proposal(sourceConversationID: presentation.sourceConversationID)
        discardCompletedSessionIfNeeded(for: target)
        let draft = makeProposalDraft(
            definitionDraft,
            definitionID: presentation.targetDefinitionID,
            expectedRevision: presentation.expectedDefinitionRevision
        )
        if var session = paneSessions[target] {
            // Reopening for a newer proposal reuses the presentation; only its content moves.
            if session.proposalID != presentation.id {
                session.draft = draft
                session.proposalID = presentation.id
                session.errorMessage = nil
                paneSessions[target] = session
            }
        } else {
            paneSessions[target] = ScheduledTaskPaneSession(
                generation: UUID(),
                draft: draft,
                proposalID: presentation.id
            )
        }
        if let generation = paneSessions[target]?.generation {
            deactivatedPaneDismissals.remove(.init(target: target, generation: generation))
        }
        proposalPaneOriginThreadID = originThreadID
        paneFocusRestorationID = target.defaultFocusRestorationID
        errorMessage = nil
        activePaneTarget = target
    }

    /// Keeps an open proposal review pointed at its conversation's current proposal.
    ///
    /// A follow-up prompt supersedes the proposal being reviewed, so the pane reloads the
    /// replacement in place; if the proposal is simply gone, the pane closes.
    func refreshActiveProposalPaneIfNeeded() {
        guard case .proposal(let sourceConversationID)? = activePaneTarget else {
            return
        }
        let target = ScheduledTaskPaneTarget.proposal(sourceConversationID: sourceConversationID)
        guard var session = paneSessions[target] else {
            return
        }
        guard let proposal = modelContext.resolveScheduledTaskProposal(sourceConversationID: sourceConversationID),
              let definitionDraft = proposal.definitionDraft else {
            // The pane's own submit already schedules its dismissal; do not race it.
            guard !session.isSubmitting,
                  !pendingPaneDismissals.contains(where: { $0.target == target }) else {
                return
            }
            deactivatePane(target, generation: session.generation)
            return
        }
        guard session.proposalID != proposal.id else {
            return
        }
        session.draft = makeProposalDraft(
            definitionDraft,
            definitionID: proposal.targetDefinitionID,
            expectedRevision: proposal.expectedDefinitionRevision
        )
        session.proposalID = proposal.id
        session.errorMessage = nil
        paneSessions[target] = session
    }

    func deactivatePane() {
        activePaneTarget = nil
    }

    func deactivatePane(_ target: ScheduledTaskPaneTarget, generation: UUID) {
        guard activePaneTarget == target,
              paneSessions[target]?.generation == generation else {
            return
        }
        let request = PaneSessionDismissalRequest(target: target, generation: generation)
        pendingPaneDismissals.insert(request)
        deactivatedPaneDismissals.insert(request)
        activePaneTarget = nil
    }

    func dismissActivePane() {
        guard let target = activePaneTarget, let generation = paneSessions[target]?.generation else {
            return
        }
        dismissPane(target, generation: generation)
    }

    func dismissPane(
        _ target: ScheduledTaskPaneTarget,
        generation: UUID,
        restoreFocus: Bool = true
    ) {
        let request = PaneSessionDismissalRequest(target: target, generation: generation)
        guard paneSessions[target]?.generation == generation else {
            pendingPaneDismissals.remove(request)
            deactivatedPaneDismissals.remove(request)
            return
        }
        pendingPaneDismissals.remove(request)
        let ownedDeactivation = deactivatedPaneDismissals.remove(request) != nil
        let shouldRestoreFocus = activePaneTarget == target || (ownedDeactivation && activePaneTarget == nil)
        paneSessions.removeValue(forKey: target)
        if activePaneTarget == target {
            activePaneTarget = nil
        }
        if restoreFocus, shouldRestoreFocus {
            paneDismissalGeneration &+= 1
        }
    }

    func updateActiveDraft(_ draft: ScheduledTaskEditorDraft) {
        guard let target = activePaneTarget,
              var session = paneSessions[target] else {
            return
        }
        session.draft = draft
        session.errorMessage = nil
        paneSessions[target] = session
    }

    func normalizeActiveProviderDependentFields() {
        guard let target = activePaneTarget,
              var session = paneSessions[target] else {
            return
        }
        normalizeProviderDependentFields(&session.draft)
        paneSessions[target] = session
    }

    func submitActivePane() {
        guard let target = activePaneTarget,
              var session = paneSessions[target],
              !session.isSubmitting else {
            return
        }
        let generation = session.generation
        session.isSubmitting = true
        session.errorMessage = nil
        paneSessions[target] = session

        do {
            // A proposal pane consumes its proposal in the same save as the definition
            // mutation, which is also what stamps the transcript widget's outcome.
            if case .proposal = target, let proposalID = session.proposalID {
                try saveDefinition(session.draft, consumingProposalID: proposalID)
            } else {
                try saveDefinition(session.draft)
            }
            guard paneSessions[target]?.generation == generation else {
                return
            }
            if target == .create {
                paneFocusRestorationID = ScheduledTaskPaneTarget.create.defaultFocusRestorationID
            }
            pendingPaneDismissals.insert(.init(target: target, generation: generation))
        } catch {
            guard var liveSession = paneSessions[target],
                  liveSession.generation == generation else {
                return
            }
            liveSession.isSubmitting = false
            liveSession.errorMessage = error.localizedDescription
            paneSessions[target] = liveSession
            reload()
        }
    }

    func saveProposal(
        _ draft: ScheduledTaskEditorDraft,
        consumingProposalID: String
    ) -> Result<Void, Error> {
        do {
            try saveDefinition(draft, consumingProposalID: consumingProposalID)
            return .success(())
        } catch {
            reload()
            return .failure(error)
        }
    }

    @discardableResult
    func save(_ draft: ScheduledTaskEditorDraft) -> Bool {
        let target = draft.definitionID.map(ScheduledTaskPaneTarget.edit) ?? .create
        if paneSessions[target] == nil {
            paneSessions[target] = ScheduledTaskPaneSession(generation: UUID(), draft: draft)
        }
        activePaneTarget = target
        updateActiveDraft(draft)

        do {
            try saveDefinition(draft)
            paneSessions.removeValue(forKey: target)
            if activePaneTarget == target {
                activePaneTarget = nil
            }
            paneDismissalGeneration &+= 1
            return true
        } catch {
            paneSessions[target]?.errorMessage = error.localizedDescription
            reload()
            return false
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func clearEditorError() {
        guard let target = activePaneTarget else {
            return
        }
        paneSessions[target]?.errorMessage = nil
    }
}

private extension ScheduledTasksViewModel {
    func saveDefinition(
        _ draft: ScheduledTaskEditorDraft,
        consumingProposalID: String? = nil
    ) throws {
        let edit = try makeDefinitionEdit(
            from: draft,
            preservesTrustedGrantSnapshot: consumingProposalID != nil
        )
        if let definitionID = draft.definitionID {
            try mutationService.edit(
                definitionID: definitionID,
                expectedRevision: draft.expectedRevision,
                edit: edit,
                at: now(),
                consumingProposalID: consumingProposalID
            )
        } else {
            try mutationService.create(
                edit: edit,
                at: now(),
                consumingProposalID: consumingProposalID
            )
        }
        errorMessage = nil
        reload()
    }

    func discardCompletedSessionIfNeeded(for target: ScheduledTaskPaneTarget) {
        guard let request = pendingPaneDismissals.first(where: { $0.target == target }) else {
            return
        }
        deactivatedPaneDismissals.remove(request)
        dismissPane(target, generation: request.generation, restoreFocus: false)
    }
}

extension ScheduledTasksViewModel {
    /// Retires a definition's cached editor session. Lives here rather than beside `delete`
    /// in `ScheduledTasksViewModel+RowActions.swift` because it writes `pendingPaneDismissals`
    /// and `paneFocusRestorationID`, whose setters are private to this file.
    func discardEditSession(definitionID: String) {
        let target = ScheduledTaskPaneTarget.edit(definitionID)
        if let generation = paneSessions[target]?.generation {
            if activePaneTarget == target {
                paneFocusRestorationID = ScheduledTaskPaneTarget.create.defaultFocusRestorationID
            }
            pendingPaneDismissals.insert(.init(target: target, generation: generation))
        }
    }
}

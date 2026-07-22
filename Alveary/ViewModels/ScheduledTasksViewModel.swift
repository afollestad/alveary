import AgentCLIKit
import Foundation
import Observation
import SwiftData

enum ScheduledTasksViewModelError: Error, LocalizedError {
    case titleRequired
    case promptRequired
    case projectRequired
    case projectNotFound
    case existingThreadRequired
    case existingThreadUnavailable
    case invalidPersistedDestination
    case runNowRejected

    var errorDescription: String? {
        switch self {
        case .titleRequired:
            "Enter a title for the scheduled task."
        case .promptRequired:
            "Enter instructions for the scheduled task."
        case .projectRequired:
            "Choose a project for this scheduled task."
        case .projectNotFound:
            "The selected project no longer exists."
        case .existingThreadRequired:
            "Choose a pinned thread for this scheduled task."
        case .existingThreadUnavailable:
            "The selected pinned thread is no longer available."
        case .invalidPersistedDestination:
            "This scheduled task has an invalid persisted destination."
        case .runNowRejected:
            "This scheduled task could not be started. It may already be starting or the scheduler may be unavailable."
        }
    }
}

enum ScheduledTaskPaneTarget: Hashable {
    case create
    case edit(String)
}

struct ScheduledTaskPaneSession: Equatable {
    let generation: UUID
    var draft: ScheduledTaskEditorDraft
    var errorMessage: String?
    var isSubmitting = false
}

@MainActor
@Observable
final class ScheduledTasksViewModel {
    @ObservationIgnored let modelContext: ModelContext
    @ObservationIgnored private let mutationService: ScheduledTaskMutationService
    @ObservationIgnored let providerDiscovery: (any AgentCLIKit.AgentProviderDiscoveryService)?
    @ObservationIgnored let settingsService: any SettingsService
    @ObservationIgnored let agentRegistry: AgentRegistry
    @ObservationIgnored private let runNowAction: @MainActor (ScheduledTaskRunNowRequest) -> Bool
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored let currentTimeZone: () -> TimeZone
    @ObservationIgnored let notificationCenter: NotificationCenter
    @ObservationIgnored var changeObservationTask: Task<Void, Never>?
    @ObservationIgnored var threadObservationTask: Task<Void, Never>?

    private(set) var tasks: [ScheduledTaskRowPresentation] = []
    private(set) var projects: [ScheduledTaskProjectOption] = []
    private(set) var pinnedThreads: [ScheduledTaskThreadOption] = []
    var providerStatuses: [String: AgentCLIKit.AgentProviderStatus] = [:]
    var providerOrdering: [String] = []
    var isLoadingProviders = false
    var pendingRunNowDefinitionIDs = Set<String>()
    private(set) var activePaneTarget: ScheduledTaskPaneTarget?
    private(set) var paneSessions: [ScheduledTaskPaneTarget: ScheduledTaskPaneSession] = [:]
    private(set) var pendingPaneDismissals: Set<PaneSessionDismissalRequest<ScheduledTaskPaneTarget>> = []
    private(set) var paneDismissalGeneration = 0
    private(set) var paneFocusRestorationID = ScheduledTaskPaneTarget.create.defaultFocusRestorationID
    private var deactivatedPaneDismissals: Set<PaneSessionDismissalRequest<ScheduledTaskPaneTarget>> = []
    var errorMessage: String?

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

        reload()
        observeChanges()
    }

    deinit {
        changeObservationTask?.cancel()
        threadObservationTask?.cancel()
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
            pinnedThreads = try makePinnedThreadOptions()
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
        paneFocusRestorationID = focusRestorationID ?? ScheduledTaskPaneTarget.create.defaultFocusRestorationID
        errorMessage = nil
        discardCompletedSessionIfNeeded(for: .create)
        if paneSessions[.create] == nil {
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

    func requestEdit(definitionID: String, focusRestorationID: String? = nil) {
        let target = ScheduledTaskPaneTarget.edit(definitionID)
        discardCompletedSessionIfNeeded(for: target)
        if paneSessions[target] == nil {
            guard let draft = makeEditDraft(definitionID: definitionID) else {
                return
            }
            paneSessions[target] = ScheduledTaskPaneSession(generation: UUID(), draft: draft)
        }
        if let generation = paneSessions[target]?.generation {
            deactivatedPaneDismissals.remove(.init(target: target, generation: generation))
        }
        paneFocusRestorationID = focusRestorationID ?? target.defaultFocusRestorationID
        errorMessage = nil
        activePaneTarget = target
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
            try saveDefinition(session.draft)
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

    func pause(_ task: ScheduledTaskRowPresentation) {
        performMutation {
            try mutationService.pause(
                definitionID: task.id,
                expectedRevision: task.revision,
                at: now()
            )
        }
    }

    func resume(_ task: ScheduledTaskRowPresentation) {
        performMutation {
            try mutationService.resume(
                definitionID: task.id,
                expectedRevision: task.revision,
                at: now()
            )
        }
    }

    func delete(_ task: ScheduledTaskRowPresentation) {
        do {
            try mutationService.delete(definitionID: task.id, expectedRevision: task.revision)
            discardEditSession(definitionID: task.id)
            errorMessage = nil
            reload()
        } catch {
            errorMessage = error.localizedDescription
            reload()
        }
    }

    func runNow(_ task: ScheduledTaskRowPresentation) {
        do {
            let request = try mutationService.prepareRunNow(
                definitionID: task.id,
                expectedRevision: task.revision,
                at: now()
            )
            guard runNowAction(request) else {
                throw ScheduledTasksViewModelError.runNowRejected
            }
            errorMessage = nil
            pendingRunNowDefinitionIDs.insert(task.id)
        } catch {
            errorMessage = error.localizedDescription
            reload()
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

    func discardEditSession(definitionID: String) {
        let target = ScheduledTaskPaneTarget.edit(definitionID)
        if let generation = paneSessions[target]?.generation {
            if activePaneTarget == target {
                paneFocusRestorationID = ScheduledTaskPaneTarget.create.defaultFocusRestorationID
            }
            pendingPaneDismissals.insert(.init(target: target, generation: generation))
        }
    }

    func discardCompletedSessionIfNeeded(for target: ScheduledTaskPaneTarget) {
        guard let request = pendingPaneDismissals.first(where: { $0.target == target }) else {
            return
        }
        deactivatedPaneDismissals.remove(request)
        dismissPane(target, generation: request.generation, restoreFocus: false)
    }

    func performMutation(_ mutation: () throws -> Void) {
        do {
            try mutation()
            errorMessage = nil
            reload()
        } catch {
            errorMessage = error.localizedDescription
            reload()
        }
    }

}

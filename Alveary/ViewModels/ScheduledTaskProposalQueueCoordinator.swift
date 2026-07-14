import Foundation
import Observation
import SwiftData

struct ScheduledTaskProposalPresentation: Identifiable, Equatable {
    let id: String
    let action: ScheduledTaskProposalAction?
    let sourceConversationID: String
    let targetDefinitionID: String?
    let expectedDefinitionRevision: Int?
    let targetTitle: String?
    let targetScheduleSummary: String?
    let definitionDraft: ScheduledTaskProposalDefinitionDraft?
    let createdAt: Date
    let conflictMessage: String?

    var isEditorProposal: Bool {
        action == .create || action == .edit
    }

    var actionTitle: String {
        switch action {
        case .create:
            "Create scheduled task"
        case .edit:
            "Edit scheduled task"
        case .pause:
            "Pause scheduled task"
        case .resume:
            "Resume scheduled task"
        case .delete:
            "Delete scheduled task"
        case .runNow:
            "Run scheduled task now"
        case nil:
            "Scheduling proposal unavailable"
        }
    }
}

@MainActor
@Observable
final class ScheduledTaskProposalQueueCoordinator {
    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let mutationService: ScheduledTaskMutationService
    @ObservationIgnored private let runNowAction: @MainActor (ScheduledTaskRunNowRequest) -> Bool
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private let saveModelContext: (ModelContext) throws -> Void
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var proposalObservationTask: Task<Void, Never>?
    @ObservationIgnored private var scheduleObservationTask: Task<Void, Never>?

    private(set) var currentProposal: ScheduledTaskProposalPresentation?
    private(set) var isResolving = false
    var errorMessage: String?

    init(
        modelContext: ModelContext,
        mutationService: ScheduledTaskMutationService,
        notificationCenter: NotificationCenter = .default,
        saveModelContext: @escaping (ModelContext) throws -> Void = { try $0.save() },
        runNow: @escaping @MainActor (ScheduledTaskRunNowRequest) -> Bool,
        now: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.mutationService = mutationService
        self.notificationCenter = notificationCenter
        self.saveModelContext = saveModelContext
        self.runNowAction = runNow
        self.now = now
        reload()
        observeChanges()
    }

    deinit {
        proposalObservationTask?.cancel()
        scheduleObservationTask?.cancel()
    }

    func reload() {
        do {
            var proposals = try fetchQueuedProposals()
            let orphaned = proposals.filter {
                modelContext.resolveConversation(conversationID: $0.sourceConversationID) == nil
            }
            if !orphaned.isEmpty {
                orphaned.forEach(modelContext.delete)
                do {
                    try saveModelContext(modelContext)
                } catch {
                    modelContext.rollback()
                    throw error
                }
                proposals = try fetchQueuedProposals()
            }
            currentProposal = proposals.first.map(makePresentation)
            if currentProposal == nil {
                errorMessage = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func reject(
        proposalID: String,
        clearingProposalErrorIn viewModel: ScheduledTasksViewModel? = nil
    ) -> Bool {
        guard !isResolving else {
            return false
        }
        guard currentProposal?.id == proposalID else {
            reload()
            return finishRejectedProposalIfAbsent(proposalID, viewModel: viewModel)
        }
        isResolving = true
        defer { isResolving = false }

        do {
            try flushPendingChanges()
            guard let proposal = try fetchProposal(id: proposalID) else {
                reload()
                viewModel?.clearEditorError()
                return true
            }
            modelContext.delete(proposal)
            try saveModelContext(modelContext)
            notificationCenter.postScheduledTaskProposalsChanged(object: self)
            errorMessage = nil
            reload()
            viewModel?.clearEditorError()
            return true
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
            return false
        }
    }

    func confirmEditorProposal(
        proposalID: String,
        draft: ScheduledTaskEditorDraft,
        viewModel: ScheduledTasksViewModel
    ) -> Bool {
        guard beginResolution(proposalID: proposalID) else {
            return false
        }
        defer { isResolving = false }

        guard let presentation = currentProposal,
              presentation.conflictMessage == nil,
              presentation.isEditorProposal,
              draft.definitionID == presentation.targetDefinitionID,
              draft.expectedRevision == presentation.expectedDefinitionRevision else {
            let message = "This scheduling proposal is stale and cannot be applied."
            errorMessage = message
            return false
        }

        let didSave = viewModel.save(draft, consumingProposalID: proposalID)
        if didSave {
            errorMessage = nil
            reload()
        } else {
            errorMessage = viewModel.editorErrorMessage
        }
        return didSave
    }

    func confirmActionProposal(proposalID: String) {
        guard beginResolution(proposalID: proposalID) else {
            return
        }
        defer { isResolving = false }

        do {
            try applyActionProposal(proposalID: proposalID)
            errorMessage = nil
            reload()
        } catch {
            errorMessage = error.localizedDescription
            reload()
        }
    }

    func clearError() {
        errorMessage = nil
    }
}

private extension ScheduledTaskProposalQueueCoordinator {
    func fetchQueuedProposals() throws -> [ScheduledTaskProposal] {
        try modelContext.fetch(FetchDescriptor<ScheduledTaskProposal>())
            .sorted(by: isEnqueuedBefore)
    }

    func isEnqueuedBefore(_ lhs: ScheduledTaskProposal, _ rhs: ScheduledTaskProposal) -> Bool {
        let lhsOrdinal = lhs.enqueueOrdinal.flatMap { $0 > 0 ? $0 : nil }
        let rhsOrdinal = rhs.enqueueOrdinal.flatMap { $0 > 0 ? $0 : nil }
        switch (lhsOrdinal, rhsOrdinal) {
        case let (lhsOrdinal?, rhsOrdinal?) where lhsOrdinal != rhsOrdinal:
            return lhsOrdinal < rhsOrdinal
        case (_?, nil):
            return false
        case (nil, _?):
            return true
        default:
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id < rhs.id
        }
    }

    func observeChanges() {
        let proposalNotifications = notificationCenter.notifications(named: .scheduledTaskProposalsChanged)
        proposalObservationTask = Task { @MainActor [weak self] in
            for await _ in proposalNotifications {
                guard !Task.isCancelled else { return }
                self?.reload()
            }
        }

        let scheduleNotifications = notificationCenter.notifications(named: .scheduledTasksChanged)
        scheduleObservationTask = Task { @MainActor [weak self] in
            for await _ in scheduleNotifications {
                guard !Task.isCancelled else { return }
                self?.reload()
            }
        }
    }

    func beginResolution(proposalID: String) -> Bool {
        guard !isResolving else {
            return false
        }
        guard currentProposal?.id == proposalID else {
            reload()
            return false
        }
        isResolving = true
        return true
    }

    func makePresentation(_ proposal: ScheduledTaskProposal) -> ScheduledTaskProposalPresentation {
        let action = proposal.action
        let definitionDraft = proposal.definitionDraft
        let conflictMessage = proposalConflictMessage(
            proposal,
            action: action,
            definitionDraft: definitionDraft
        )
        return proposalPresentation(proposal, action: action, definitionDraft: definitionDraft, conflictMessage: conflictMessage)
    }

    func proposalConflictMessage(
        _ proposal: ScheduledTaskProposal,
        action: ScheduledTaskProposalAction?,
        definitionDraft: ScheduledTaskProposalDefinitionDraft?
    ) -> String? {
        if action == nil {
            return "This proposal uses an unsupported action."
        }
        if !proposal.hasValidActionShape {
            return "This proposal's persisted action details are inconsistent."
        }
        if action == .create || action == .edit, definitionDraft == nil {
            return "This proposal's task details cannot be read."
        }
        if let definitionDraft,
           definitionDraft.workspaceKind == .project,
           proposal.project?.path != definitionDraft.projectPath {
            return "The project selected for this proposal is no longer available."
        }
        guard action != .create else {
            return nil
        }
        guard let definitionID = proposal.targetDefinitionID,
              let expectedRevision = proposal.expectedDefinitionRevision else {
            return "This proposal is missing its scheduled task identity."
        }
        guard let definition = modelContext.resolveScheduledTask(id: definitionID) else {
            return "The scheduled task for this proposal was deleted."
        }
        guard definition.revision == expectedRevision else {
            return "This scheduled task changed after the proposal was opened."
        }
        return nil
    }

    func applyActionProposal(proposalID: String) throws {
        guard let presentation = currentProposal else {
            throw ScheduledTaskMutationError.proposalNotFound
        }
        if let conflictMessage = presentation.conflictMessage {
            throw ScheduledTaskProposalQueueError.conflict(conflictMessage)
        }
        guard let definitionID = presentation.targetDefinitionID,
              let expectedRevision = presentation.expectedDefinitionRevision else {
            throw ScheduledTaskProposalQueueError.invalidProposal
        }

        switch presentation.action {
        case .pause:
            try mutationService.pause(
                definitionID: definitionID,
                expectedRevision: expectedRevision,
                at: now(),
                consumingProposalID: proposalID
            )
        case .resume:
            try mutationService.resume(
                definitionID: definitionID,
                expectedRevision: expectedRevision,
                at: now(),
                consumingProposalID: proposalID
            )
        case .delete:
            try mutationService.delete(
                definitionID: definitionID,
                expectedRevision: expectedRevision,
                consumingProposalID: proposalID
            )
        case .runNow:
            try applyRunNowProposal(
                proposalID: proposalID,
                definitionID: definitionID,
                expectedRevision: expectedRevision
            )
        case .create, .edit, nil:
            throw ScheduledTaskProposalQueueError.invalidProposal
        }
    }

    func applyRunNowProposal(
        proposalID: String,
        definitionID: String,
        expectedRevision: Int
    ) throws {
        let request = try mutationService.prepareRunNow(
            definitionID: definitionID,
            expectedRevision: expectedRevision,
            at: now(),
            idempotencyKey: proposalID
        )
        guard runNowAction(request) else {
            throw ScheduledTaskProposalQueueError.runNowRejected
        }
        try mutationService.consumeProposal(id: proposalID)
    }

    func proposalPresentation(
        _ proposal: ScheduledTaskProposal,
        action: ScheduledTaskProposalAction?,
        definitionDraft: ScheduledTaskProposalDefinitionDraft?,
        conflictMessage: String?
    ) -> ScheduledTaskProposalPresentation {
        ScheduledTaskProposalPresentation(
            id: proposal.id,
            action: action,
            sourceConversationID: proposal.sourceConversationID,
            targetDefinitionID: proposal.targetDefinitionID,
            expectedDefinitionRevision: proposal.expectedDefinitionRevision,
            targetTitle: proposal.targetTitleSnapshot,
            targetScheduleSummary: proposal.targetScheduleSummarySnapshot,
            definitionDraft: definitionDraft,
            createdAt: proposal.createdAt,
            conflictMessage: conflictMessage
        )
    }

    func flushPendingChanges() throws {
        guard modelContext.hasChanges else {
            return
        }
        try saveModelContext(modelContext)
    }

    func finishRejectedProposalIfAbsent(
        _ proposalID: String,
        viewModel: ScheduledTasksViewModel?
    ) -> Bool {
        do {
            guard try fetchProposal(id: proposalID) == nil else {
                return false
            }
            viewModel?.clearEditorError()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func fetchProposal(id: String) throws -> ScheduledTaskProposal? {
        try modelContext.fetch(
            FetchDescriptor<ScheduledTaskProposal>(
                predicate: #Predicate { proposal in
                    proposal.id == id
                }
            )
        ).first
    }
}

private enum ScheduledTaskProposalQueueError: LocalizedError {
    case conflict(String)
    case invalidProposal
    case runNowRejected

    var errorDescription: String? {
        switch self {
        case .conflict(let message):
            message
        case .invalidProposal:
            "This scheduling proposal cannot be applied."
        case .runNowRejected:
            "This scheduled task could not be started. It may already be starting or the scheduler may be unavailable."
        }
    }
}

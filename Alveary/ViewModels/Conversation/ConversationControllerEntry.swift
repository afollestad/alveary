import AgentCLIKit
import Foundation

@MainActor
final class ControllerEntry {
    let viewModel: ConversationViewModel
    var isInternallyRetained = false
    var terminalMaintenanceTask: Task<Void, Never>?
    var pendingTerminals: [PendingControllerTerminal] = []
    var trackedTurn: TrackedControllerTurn?
    var deferredGoalBoundary: ConversationTerminalBoundary?
    var needsSuspension = false
    var quiescenceMaintenanceFailed = false
    var lastConsumedTerminalBoundarySequence: UInt64

    private var leases: [UUID: LeaseState] = [:]
    private var isViewLifecycleActive = false
    private var isBackgroundLifecycleActive = false

    init(viewModel: ConversationViewModel) {
        self.viewModel = viewModel
        self.lastConsumedTerminalBoundarySequence = viewModel.state.lastControllerTerminalBoundary?.sequence ?? 0
    }

    var observedState: ObservedControllerState {
        ObservedControllerState(
            isTurnActive: viewModel.turnState.isActive,
            activityVisibility: viewModel.state.currentTurnActivityVisibility,
            pendingApprovalID: viewModel.state.pendingToolApproval?.request.toolUseId,
            pendingQuestionID: viewModel.state.grouper.latestUnansweredPrompt?.id,
            isSendingMessage: viewModel.state.isSendingMessage,
            hasInitialSetupTask: viewModel.initialSetupTask != nil,
            hasQueueDrainTask: viewModel.queueDrainTask != nil,
            hasSetupPhase: viewModel.state.setupPhase != nil,
            isReconfiguringSession: viewModel.state.isReconfiguringSession,
            hasSessionHandoff: viewModel.state.hasActiveSessionHandoff ||
                viewModel.state.isAutomaticSessionHandoffPending,
            isGeneratingCommitMessage: viewModel.state.isGeneratingCommitMessage,
            hasNonterminalGoal: viewModel.state.goalSnapshot?.status.isTerminal == false,
            terminalBoundary: viewModel.state.lastControllerTerminalBoundary,
            hasPendingPersistence: viewModel.hasPendingPersistence
        )
    }

    var controllerPhase: ControllerPhase {
        let snapshot = observedState
        if let pendingQuestionID = snapshot.pendingQuestionID {
            return .waitingForQuestion(interactionID: pendingQuestionID)
        }
        if let pendingApprovalID = snapshot.pendingApprovalID {
            return .waitingForApproval(interactionID: pendingApprovalID)
        }
        if snapshot.isTurnActive, snapshot.activityVisibility == .visible {
            return .active
        }
        if snapshot.isTurnActive || snapshot.hasNonterminalGoal {
            return .hiddenActive
        }
        return .idle
    }

    var hasActiveWork: Bool {
        let snapshot = observedState
        return snapshot.isTurnActive ||
            snapshot.isSendingMessage ||
            snapshot.hasInitialSetupTask ||
            snapshot.hasQueueDrainTask ||
            snapshot.hasSetupPhase ||
            snapshot.isReconfiguringSession ||
            snapshot.hasSessionHandoff ||
            snapshot.isGeneratingCommitMessage ||
            snapshot.hasNonterminalGoal
    }

    var hasUnpublishedTerminal: Bool {
        pendingTerminals.contains { !$0.terminalWasPublished }
    }

    var hasTerminalMaintenanceFailure: Bool {
        quiescenceMaintenanceFailed || pendingTerminals.contains { $0.status == .failed }
    }

    var canEvict: Bool {
        leases.isEmpty &&
            !isInternallyRetained &&
            !hasActiveWork &&
            !viewModel.hasPendingPersistence
    }

    var defersAutomaticSuspension: Bool {
        leases.values.contains(where: \.defersAutomaticSuspension)
    }

    func registerLease(
        id: UUID,
        kind: ConversationControllerLeaseKind,
        defersAutomaticSuspension: Bool = false
    ) {
        leases[id] = LeaseState(
            kind: kind,
            isActive: false,
            defersAutomaticSuspension: defersAutomaticSuspension
        )
    }

    func setLease(id: UUID, active: Bool) {
        guard var lease = leases[id] else {
            return
        }
        lease.isActive = active
        leases[id] = lease
    }

    func removeLease(id: UUID) {
        leases.removeValue(forKey: id)
    }

    func leaseDefersAutomaticSuspension(id: UUID) -> Bool {
        leases[id]?.defersAutomaticSuspension == true
    }

    func reconcileLifecycles() {
        let shouldActivateView = leases.values.contains { $0.kind == .view && $0.isActive }
        let shouldActivateBackground = isInternallyRetained ||
            leases.values.contains { $0.kind == .background && $0.isActive }

        if shouldActivateBackground, !isBackgroundLifecycleActive {
            isBackgroundLifecycleActive = true
            viewModel.activateBackgroundLifecycle()
        }
        if shouldActivateView, !isViewLifecycleActive {
            isViewLifecycleActive = true
            viewModel.activateViewLifecycle()
        }
        if !shouldActivateView, isViewLifecycleActive {
            isViewLifecycleActive = false
            viewModel.deactivateViewLifecycle()
        }
        if !shouldActivateBackground, isBackgroundLifecycleActive {
            isBackgroundLifecycleActive = false
            viewModel.deactivateBackgroundLifecycle()
        }
    }

    func invalidate() {
        terminalMaintenanceTask?.cancel()
        terminalMaintenanceTask = nil
        leases.removeAll()
        isInternallyRetained = false
        needsSuspension = false
        reconcileLifecycles()
    }
}

struct TrackedControllerTurn {
    let turn: ConversationControllerTurn
    var state: ConversationControllerOutcome.State
    var wasPublished: Bool
}

struct PendingControllerTerminal {
    enum Status: Equatable {
        case pending
        case failed
        case retryPending
    }

    let boundarySequence: UInt64
    let turn: ConversationControllerTurn
    let preterminalState: ConversationControllerOutcome.State
    var preterminalWasPublished: Bool
    let terminalState: ConversationControllerOutcome.State
    var terminalWasPublished = false
    var status: Status = .pending
}

struct LeaseState {
    let kind: ConversationControllerLeaseKind
    var isActive: Bool
    let defersAutomaticSuspension: Bool
}

struct ObservedControllerState: Equatable {
    let isTurnActive: Bool
    let activityVisibility: AgentTurnActivityVisibility
    let pendingApprovalID: String?
    let pendingQuestionID: String?
    let isSendingMessage: Bool
    let hasInitialSetupTask: Bool
    let hasQueueDrainTask: Bool
    let hasSetupPhase: Bool
    let isReconfiguringSession: Bool
    let hasSessionHandoff: Bool
    let isGeneratingCommitMessage: Bool
    let hasNonterminalGoal: Bool
    let terminalBoundary: ConversationTerminalBoundary?
    let hasPendingPersistence: Bool
}

enum ControllerPhase: Equatable {
    case idle
    case active
    case hiddenActive
    case waitingForApproval(interactionID: String?)
    case waitingForQuestion(interactionID: String?)
}

final class OutcomeHub {
    var nextEpoch: UInt64 = 0
    var current: ConversationControllerOutcome?
    var continuations: [UUID: AsyncStream<ConversationControllerOutcome>.Continuation] = [:]
}

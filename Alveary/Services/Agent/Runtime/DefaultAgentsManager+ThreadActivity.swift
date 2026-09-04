import AgentCLIKit
import Foundation

extension DefaultAgentsManager {
    func markCurrentTurnActivityVisibility(
        _ visibility: AgentTurnActivityVisibility,
        conversationId: String
    ) {
        guard let managedBuffer = eventBuffers[conversationId] else {
            return
        }
        managedBuffer.terminalNotificationVisibility = nil
        if visibility == .visible {
            managedBuffer.currentTurnActivityVisibility = .visible
            managedBuffer.hasRecordedTerminalThreadActivity = false
        } else if managedBuffer.currentTurnActivityVisibility != .visible {
            managedBuffer.currentTurnActivityVisibility = .hidden
        }
    }

    func recordVisibleTurnEndedIfNeeded(conversationId: String) {
        guard let managedBuffer = eventBuffers[conversationId],
              managedBuffer.currentTurnActivityVisibility == .visible,
              !managedBuffer.hasRecordedTerminalThreadActivity else {
            return
        }
        managedBuffer.hasRecordedTerminalThreadActivity = true
        managedBuffer.currentTurnActivityVisibility = .hidden
        managedBuffer.lastKnownRuntimeTurnActive = false
        Task { @MainActor [threadActivityRecorder] in
            threadActivityRecorder.recordVisibleTurnEnded(conversationId: conversationId)
        }
    }

    func recordVisibleTurnEndedForTerminalEventIfNeeded(
        _ event: ConversationEvent,
        conversationId: String
    ) {
        switch event {
        case .tokens:
            guard let payload = TokenEventPayload(event),
                  payload.recordsThreadActivityTerminalBoundary else {
                return
            }
            recordVisibleTurnEndedIfNeeded(conversationId: conversationId)
        case .stop, .error:
            recordVisibleTurnEndedIfNeeded(conversationId: conversationId)
        case .runtimeActivity(let state, _, let outcome):
            guard state == .idle,
                  outcome.recordsThreadActivityTerminalBoundary else {
                return
            }
            recordVisibleTurnEndedIfNeeded(conversationId: conversationId)
        default:
            break
        }
    }

    /// The turn-ended status can land before the terminal event it describes, since AgentCLIKit
    /// yields them on separate streams. Stash the visibility as the event path does, or the late
    /// terminal token reads an already-hidden turn and its notification is dropped.
    func handleRuntimeTurnActiveStatus(
        _ status: AgentCLIKit.AgentRuntimeStatus,
        conversationId: String
    ) {
        guard let managedBuffer = eventBuffers[conversationId] else {
            return
        }
        let wasTurnActive = managedBuffer.lastKnownRuntimeTurnActive
        managedBuffer.lastKnownRuntimeTurnActive = status.isTurnActive
        guard wasTurnActive, !status.isTurnActive else {
            return
        }
        if managedBuffer.currentTurnActivityVisibility == .visible {
            managedBuffer.terminalNotificationVisibility = .visible
        }
        recordVisibleTurnEndedIfNeeded(conversationId: conversationId)
    }
}

private extension TokenEventPayload {
    var recordsThreadActivityTerminalBoundary: Bool {
        if isError || !permissionDenials.isEmpty {
            return true
        }
        guard let stopReason else {
            return isTerminal
        }
        return stopReason != ConversationEvent.interimUsageStopReason &&
            stopReason != "tool_use"
    }
}

private extension ConversationRuntimeActivityOutcome {
    var recordsThreadActivityTerminalBoundary: Bool {
        switch self {
        case .completed, .failed, .interrupted:
            return true
        case .unknown:
            return false
        }
    }
}

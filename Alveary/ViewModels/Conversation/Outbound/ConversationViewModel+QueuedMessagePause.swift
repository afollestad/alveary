import Foundation

extension ConversationViewModel {
    func pauseQueuedMessagesAfterInterruptionIfNeeded() {
        guard state.messageQueue.peekNext() != nil,
              state.currentTurnActivityVisibility == .visible,
              !state.isHandingOffSession,
              state.failedSessionHandoffMessage == nil,
              !state.isGeneratingCommitMessage,
              !state.isDrainingCommitMessageGenerationEvents else {
            return
        }
        state.queuedMessagesPauseReason = .interrupted
    }

    func clearQueuedMessagesPauseIfQueueEmpty() {
        guard state.messageQueue.peekNext() == nil else {
            return
        }
        state.queuedMessagesPauseReason = nil
        state.pausedQueueSendConfirmation = nil
    }

    func resumeQueuedMessages() {
        state.queuedMessagesPauseReason = nil
        state.pausedQueueSendConfirmation = nil
        scheduleQueueDrainIfNeeded()
    }

    func clearPausedQueuedMessages() {
        guard state.queuedMessagesPauseReason != nil else {
            return
        }
        state.messageQueue.clear()
        state.queuedMessagesPauseReason = nil
        state.pausedQueueSendConfirmation = nil
    }
}

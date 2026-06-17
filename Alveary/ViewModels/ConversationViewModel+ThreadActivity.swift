extension ConversationViewModel {
    func markVisibleTurnStarted() {
        markPromptDismissalNewOutboundTurnStarted()
        state.currentTurnActivityVisibility = .visible
        state.hasRecordedLocalTurnEndActivity = false
    }

    func markHiddenTurnStarted() {
        if state.currentTurnActivityVisibility != .visible {
            state.currentTurnActivityVisibility = .hidden
        }
        state.hasRecordedLocalTurnEndActivity = false
    }

    func beginHiddenActivityTurn() {
        markHiddenTurnStarted()
        state.turnState.beginTurn()
    }

    func recordInitialPromptOutboundActivity() {
        threadActivityRecorder.recordVisibleOutbound(conversationId: conversation.id)
    }

    func recordLocalVisibleTurnEndedIfNeeded() {
        guard state.currentTurnActivityVisibility == .visible,
              !state.hasRecordedLocalTurnEndActivity else {
            return
        }
        state.hasRecordedLocalTurnEndActivity = true
        state.currentTurnActivityVisibility = .hidden
        threadActivityRecorder.recordVisibleTurnEnded(conversationId: conversation.id)
    }
}

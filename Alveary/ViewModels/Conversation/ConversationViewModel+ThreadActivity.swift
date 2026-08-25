extension ConversationViewModel {
    func markVisibleTurnStarted(isSessionHandoffSeed: Bool = false) {
        markPromptDismissalNewOutboundTurnStarted()
        controllerTerminalFailureMessage = nil
        // The credential notice has to outlive the turn that failed, not a turn the user just started:
        // signing in and sending again would otherwise leave a stale Sign In banner up for good.
        state.providerAuthenticationFailure = nil
        clearDurableTurnFailure()
        state.currentTurnActivityVisibility = .visible
        state.hasRecordedLocalTurnEndActivity = false
        state.isSessionHandoffSeedTurnActive = isSessionHandoffSeed
        state.isDrainingCommitMessageGenerationEvents = false
    }

    func markHiddenTurnStarted() {
        if state.currentTurnActivityVisibility != .visible {
            state.currentTurnActivityVisibility = .hidden
        }
        state.hasRecordedLocalTurnEndActivity = false
        state.isSessionHandoffSeedTurnActive = false
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

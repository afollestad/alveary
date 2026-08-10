extension ConversationViewModel {
    func acknowledgeLateHiddenSessionHandoffTerminalEvent(_ event: ConversationEvent) -> Bool {
        switch event {
        case .runtimeActivity, .error:
            state.activeRuntimeActivityTurnId = nil
            state.clearStreamingText()
            state.isCancellingTurn = false
            state.endTurn()
            scheduleSave()
        default:
            break
        }
        return false
    }

    func handleHiddenSessionHandoffRuntimeActivity(
        state activityState: ConversationRuntimeActivityState,
        turnId: String?,
        outcome: ConversationRuntimeActivityOutcome
    ) -> Bool {
        switch activityState {
        case .active:
            state.activeRuntimeActivityTurnId = turnId
            state.turnState.beginTurn()
            scheduleSave()
        case .idle:
            handleHiddenSessionHandoffRuntimeIdle(turnId: turnId, outcome: outcome)
        }
        return false
    }

    func failHiddenSessionHandoffFromError(_ message: String) -> Bool {
        failHiddenSessionHandoff("Session handoff failed: \(message)")
        scheduleSave()
        return false
    }
}

private extension ConversationViewModel {
    func handleHiddenSessionHandoffRuntimeIdle(
        turnId: String?,
        outcome: ConversationRuntimeActivityOutcome
    ) {
        guard !shouldIgnoreRuntimeActivityIdle(turnId: turnId) else {
            scheduleSave()
            return
        }

        state.activeRuntimeActivityTurnId = nil
        state.clearStreamingText()
        switch outcome {
        case .unknown, .completed:
            completeHiddenSessionHandoffFromRuntimeActivity()
        case .failed(let message):
            failHiddenSessionHandoff(message)
            scheduleSave()
        case .interrupted:
            state.lastTurnInterrupted = true
            failHiddenSessionHandoff("Session handoff interrupted.")
            scheduleSave()
        }
    }

    func completeHiddenSessionHandoffFromRuntimeActivity() {
        let output = SessionHandoffPromptBuilder.editableHandoffOutput(state.hiddenHandoffResponse)
        guard !output.isEmpty else {
            state.endTurn()
            failHiddenSessionHandoff("Session handoff failed: the hidden handoff prompt returned no context.")
            scheduleSave()
            return
        }

        state.endTurn()
        scheduleSave()
        Task { @MainActor [self] in
            await finishHiddenSessionHandoff(with: output)
        }
    }
}

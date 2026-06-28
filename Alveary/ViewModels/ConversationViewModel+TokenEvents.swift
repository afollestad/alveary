extension ConversationViewModel {
    func handleTokenEvent(_ payload: TokenEventPayload) -> TokenEventPersistence {
        let hadStreamingText = state.streamingText != nil
        state.clearAssistantStreamingText()
        guard payload.stopReason != ConversationEvent.interimUsageStopReason else { return .persistTokens }
        state.clearThoughtText(ifNeeded: payload.clearsLiveThoughtText)
        guard !handleToolDeferredTokenIfNeeded(payload) else { return .persistTokens }
        if !payload.isError && payload.permissionDenials.isEmpty {
            markAutomaticSessionHandoffPendingIfNeeded(for: payload)
        }
        guard payload.completesTurn else { return .persistTokens }
        state.activeRuntimeActivityTurnId = nil
        clearResolvedPendingToolApprovalIfNeeded()
        let didQueueExitPlanModeFollowUp = markPendingExitPlanModeFollowUpReadyAfterTerminalToken(payload)

        if let earlyPersistence = earlyTokenPersistence(payload, hadStreamingText: hadStreamingText) {
            return earlyPersistence
        }

        state.isCancellingTurn = false
        if payload.isError || !payload.permissionDenials.isEmpty {
            handleFailedTokenTurn(payload)
        }

        if !payload.isError && payload.permissionDenials.isEmpty {
            if shouldTriggerAutomaticSessionHandoff(for: payload) {
                state.endTurn()
                Task { @MainActor [self] in await startSessionHandoff(trigger: .automatic) }
            } else if isAwaitingAutomaticSessionHandoffTurnCompletion(for: payload) {
                // Keep queued messages parked until the real terminal token starts handoff.
            } else {
                handleTurnCompleted()
            }
        } else if didQueueExitPlanModeFollowUp || !payload.permissionDenials.isEmpty {
            handleTurnCompleted()
        } else {
            state.endTurn()
        }

        return .persistTokens
    }

    func earlyTokenPersistence(
        _ payload: TokenEventPayload,
        hadStreamingText: Bool
    ) -> TokenEventPersistence? {
        if let slashCommandNotice = state.synthesizedSlashCommandFailureNotice(
            for: payload,
            hadStreamingText: hadStreamingText
        ) {
            state.isCancellingTurn = false
            state.lastTurnInterrupted = false
            state.lastTurnError = nil
            state.pendingSyntheticAssistantDuplicateText = slashCommandNotice
            handleTurnCompleted()
            return .persistSyntheticAssistant(message: slashCommandNotice)
        }

        if isConfirmedTurnInterruption(
            isError: payload.isError,
            stopReason: payload.stopReason,
            permissionDenials: payload.permissionDenials
        ) {
            handleInterruptedTokenTurn()
            return .persistSyntheticStop(message: ConversationInterruption.displayMessage)
        }

        guard state.lastTurnInterrupted, payload.isError, payload.permissionDenials.isEmpty else {
            return nil
        }

        state.isCancellingTurn = false
        state.lastTurnError = nil
        state.endTurn()
        return .dropTokens
    }

    func handleInterruptedTokenTurn() {
        state.activeRuntimeActivityTurnId = nil
        state.isAutomaticSessionHandoffPending = false
        state.isCancellingTurn = false
        state.lastTurnError = nil
        state.lastTurnInterrupted = true
        markTranscriptActivityInterrupted()
        pauseQueuedMessagesAfterInterruptionIfNeeded()
        state.endTurn()
    }

    func handleFailedTokenTurn(_ payload: TokenEventPayload) {
        state.activeRuntimeActivityTurnId = nil
        state.isAutomaticSessionHandoffPending = false
        state.lastTurnInterrupted = false
        guard payload.permissionDenials.isEmpty else {
            state.lastTurnError = nil
            return
        }
        guard !shouldSuppressTokenErrorComposerMessage(payload) else {
            state.lastTurnError = nil
            return
        }
        state.lastTurnError = ConversationErrorDisplayPolicy.tokenErrorMessage(stopReason: payload.stopReason)
    }

    func shouldSuppressTokenErrorComposerMessage(_ payload: TokenEventPayload) -> Bool {
        if state.grouper.items.containsCurrentTurnTranscriptError {
            return true
        }
        return ConversationErrorDisplayPolicy.isGenericStopReason(payload.stopReason) &&
            state.grouper.items.containsCurrentTurnAssistantMessage
    }
}

private extension TokenEventPayload {
    var clearsLiveThoughtText: Bool {
        completesTurn || stopReason == "tool_deferred"
    }
}

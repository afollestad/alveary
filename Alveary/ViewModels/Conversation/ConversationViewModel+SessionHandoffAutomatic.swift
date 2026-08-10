import Foundation

extension ConversationViewModel {
    func markAutomaticSessionHandoffPendingIfNeeded(for payload: TokenEventPayload) {
        guard !defersOrdinaryScheduledOutbound else {
            state.isAutomaticSessionHandoffPending = false
            return
        }
        let settings = settingsService.current
        guard settings.contextManagementEnabled else {
            state.isAutomaticSessionHandoffPending = false
            return
        }
        guard !state.hasActiveSessionHandoff,
              !state.isSendingMessage,
              !state.isReconfiguringSession,
              state.pendingToolApproval == nil,
              !hasUnansweredPrompt else {
            return
        }

        markAutomaticSessionHandoffPendingIfNeeded(payload, settings: settings)
    }

    func shouldTriggerAutomaticSessionHandoff(for payload: TokenEventPayload) -> Bool {
        markAutomaticSessionHandoffPendingIfNeeded(for: payload)
        return consumeCompletedAutomaticSessionHandoffIfNeeded(payload)
    }

    func isAwaitingAutomaticSessionHandoffTurnCompletion(for payload: TokenEventPayload) -> Bool {
        state.isAutomaticSessionHandoffPending && !isCompletedTurnForAutomaticSessionHandoff(payload)
    }
}

private extension ConversationViewModel {
    func markAutomaticSessionHandoffPendingIfNeeded(_ payload: TokenEventPayload, settings: AppSettings) {
        guard let contextWindowSize = payload.contextWindowSize, contextWindowSize > 0 else {
            return
        }

        let providerID = conversation.provider ?? settings.defaultProvider
        let contextUsedTokens = ContextTokenAccounting(providerID: providerID).contextUsedTokens(
            input: payload.input,
            cacheRead: payload.cacheRead,
            cacheCreation: payload.cacheCreation
        )
        let threshold = AppSettings.normalizedSessionHandoffWindowPercentage(
            settings.sessionHandoffWindowPercentage
        )
        if Double(contextUsedTokens) / Double(contextWindowSize) * 100 >= Double(threshold) {
            state.isAutomaticSessionHandoffPending = true
        }
    }

    func consumeCompletedAutomaticSessionHandoffIfNeeded(_ payload: TokenEventPayload) -> Bool {
        guard state.isAutomaticSessionHandoffPending,
              isCompletedTurnForAutomaticSessionHandoff(payload) else {
            return false
        }

        state.isAutomaticSessionHandoffPending = false
        return true
    }

    func isCompletedTurnForAutomaticSessionHandoff(_ payload: TokenEventPayload) -> Bool {
        !payload.isError && payload.permissionDenials.isEmpty && payload.completesTurn
    }
}

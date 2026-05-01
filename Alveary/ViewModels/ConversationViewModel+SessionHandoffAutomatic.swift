import Foundation

extension ConversationViewModel {
    func shouldTriggerAutomaticSessionHandoff(for payload: TokenEventPayload) -> Bool {
        let settings = settingsService.current
        guard settings.contextManagementEnabled else {
            state.isAutomaticSessionHandoffPending = false
            return false
        }
        guard !state.hasActiveSessionHandoff,
              !state.isSendingMessage,
              !state.isReconfiguringSession,
              state.pendingToolApproval == nil,
              !hasUnansweredPrompt else {
            return false
        }

        markAutomaticSessionHandoffPendingIfNeeded(payload, settings: settings)
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

        let contextUsedTokens = payload.input + payload.cacheRead + payload.cacheCreation
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
        guard !payload.isError,
              payload.permissionDenials.isEmpty,
              let stopReason = payload.stopReason?.trimmingCharacters(in: .whitespacesAndNewlines),
              !stopReason.isEmpty else {
            return false
        }

        return stopReason != ConversationEvent.interimUsageStopReason
    }
}

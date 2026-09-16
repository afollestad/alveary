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
              !state.isSendingMessage || capabilityHarnessID == "opencode",
              !state.isReconfiguringSession,
              state.pendingToolApproval == nil,
              !hasUnansweredPrompt else {
            return
        }

        markAutomaticSessionHandoffPendingIfNeeded(payload, settings: settings)
    }

    func shouldTriggerAutomaticSessionHandoff(for payload: TokenEventPayload) -> Bool {
        markAutomaticSessionHandoffPendingIfNeeded(for: payload)
        guard capabilityHarnessID != "opencode" || !state.isSendingMessage else { return false }
        return consumeCompletedAutomaticSessionHandoffIfNeeded(payload)
    }

    /// Native submissions can finish while the reservation still blocks handoff; keep queued work behind that boundary.
    func resumeOpenCodeAutomaticHandoffAfterSubmissionIfNeeded() -> Bool {
        guard capabilityHarnessID == "opencode", state.isAutomaticSessionHandoffPending,
              !state.turnState.isActive, !state.isSendingMessage else { return false }
        guard state.lastTurnError == nil, !state.lastTurnInterrupted, !state.isCancellingTurn else {
            state.isAutomaticSessionHandoffPending = false
            return false
        }
        Task { @MainActor [self] in
            guard state.isAutomaticSessionHandoffPending else { return }
            state.isAutomaticSessionHandoffPending = false
            await startSessionHandoff(trigger: .automatic)
        }
        return true
    }

    func isAwaitingAutomaticSessionHandoffTurnCompletion(for payload: TokenEventPayload) -> Bool {
        state.isAutomaticSessionHandoffPending && !isCompletedTurnForAutomaticSessionHandoff(payload)
    }
}

private extension ConversationViewModel {
    func markAutomaticSessionHandoffPendingIfNeeded(_ payload: TokenEventPayload, settings: AppSettings) {
        let harnessID = capabilityHarnessID
        let payload = automaticHandoffUsagePayload(payload, harnessID: harnessID)
        guard let contextWindowSize = payload.contextWindowSize, contextWindowSize > 0 else {
            if harnessID == "opencode" { state.isAutomaticSessionHandoffPending = false }
            return
        }

        let contextUsedTokens = ContextTokenAccounting(harnessID: harnessID).contextUsedTokens(
            input: payload.input,
            cacheRead: payload.cacheRead,
            cacheCreation: payload.cacheCreation
        )
        let threshold = AppSettings.normalizedSessionHandoffWindowPercentage(
            settings.sessionHandoffWindowPercentage
        )
        let exceedsThreshold = Double(contextUsedTokens) / Double(contextWindowSize) * 100 >= Double(threshold)
        if harnessID == "opencode" {
            // A native compaction can lower the latest measurement before the root turn finishes.
            state.isAutomaticSessionHandoffPending = exceedsThreshold
        } else if exceedsThreshold {
            state.isAutomaticSessionHandoffPending = true
        }
    }

    /// OpenCode finishes with a count-free boundary. Read its latest measured window here so
    /// interim usage during a tool approval or before native compaction cannot decide the handoff.
    func automaticHandoffUsagePayload(_ payload: TokenEventPayload, harnessID: String) -> TokenEventPayload {
        guard harnessID == "opencode", payload.isTerminal, payload.contextWindowSize == nil,
              payload.input == 0, payload.output == 0, payload.cacheRead == 0, payload.cacheCreation == 0 else { return payload }
        let records = conversationEventRecords()
        let recentRecords: ArraySlice<ConversationEventRecord>
        if let compaction = records.lastIndex(where: { $0.type == ConversationContextCompaction.completedType }) {
            // Summary-generation usage describes the old window; the compacted window is unknown until the next model request.
            recentRecords = records[records.index(after: compaction)...]
        } else {
            recentRecords = records[...]
        }
        guard let record = recentRecords.last(where: {
            $0.type == ConversationEventRecord.tokensType && $0.stopReason == ConversationEvent.interimUsageStopReason
        }) else { return payload }
        return TokenEventPayload(
            input: record.tokenInput, output: record.tokenOutput, cacheRead: record.tokenCacheRead,
            cacheCreation: record.tokenCacheCreation, isError: payload.isError, stopReason: payload.stopReason,
            contextWindowSize: record.contextWindowSize, permissionDenials: payload.permissionDenials, isTerminal: payload.isTerminal
        )
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

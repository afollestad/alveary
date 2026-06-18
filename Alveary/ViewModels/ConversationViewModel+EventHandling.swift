extension ConversationViewModel {
    func handleEvent(_ event: ConversationEvent) {
        if handleProviderSessionMetadataChanged(event) {
            scheduleSave()
            return
        }

        guard shouldPersistEvent(event) else {
            return
        }
        persistEventRecord(for: event)
        handlePostPersistEvent(event)
    }

    func shouldIgnoreRuntimeActivityIdle(turnId: String?) -> Bool {
        guard let activeRuntimeActivityTurnId = state.activeRuntimeActivityTurnId,
              let turnId else {
            return false
        }
        return activeRuntimeActivityTurnId != turnId
    }
}

private extension ConversationViewModel {
    // swiftlint:disable:next cyclomatic_complexity
    func shouldPersistEvent(_ event: ConversationEvent) -> Bool {
        if state.isHandingOffSession || state.failedSessionHandoffMessage != nil {
            return shouldPersistHiddenSessionHandoffEvent(event)
        }

        if shouldSuppressPromptDismissalEvent(event) || shouldSuppressPromptDismissalFallout(event) {
            return false
        }

        if shouldSuppressInterruptedTurnFallout(event) { return false }

        switch event {
        case .sessionInit,
             .providerSessionMetadataChanged:
            return false

        case .permissionModeChanged(let permissionMode):
            return handlePermissionModeChanged(permissionMode)

        case .collaborationModeChanged(let isPlanModeEnabled):
            return handleCollaborationModeChanged(isPlanModeEnabled)

        case .toolCall(_, let name, _, _, _):
            clearApprovedExitPlanModeApprovalAfterImplementationToolCall(toolName: name)
            return !persistSubAgentStartIfNeeded(for: event)
        case .toolResult(let id, _, let isError, _, _):
            clearApprovedExitPlanModeApprovalAfterToolResult(toolUseId: id, isError: isError)
            return true
        case .messageChunk(let text, let parentToolUseId):
            return handleMessageChunk(text, parentToolUseId: parentToolUseId)

        case .message(let role, let content, _):
            return shouldPersistMessageEvent(role: role, content: content)

        case .steeredConversation(let inputID): return shouldPersistSteeredConversation(inputID: inputID)
        case .tokens:
            guard let payload = TokenEventPayload(event) else { return true }
            return shouldPersistTokensEvent(payload)

        case .contextCompactionStarted, .contextCompactionCompleted, .contextCompactionFailed:
            state.clearStreamingText()
            return true

        case .toolApprovalRequested(let approval):
            return handleToolApprovalRequested(approval)

        case .toolApprovalFailed(let failure):
            return handleToolApprovalFailed(failure)

        case .runtimeActivity(let activityState, let turnId, let outcome):
            return handleRuntimeActivity(state: activityState, turnId: turnId, outcome: outcome)

        case .stop(let message):
            return shouldPersistStopEvent(message: message)

        case .error(let message):
            return shouldPersistErrorEvent(message: message)

        case .subAgentStarted, .subAgentProgress, .subAgentCompleted:
            return handleSubAgentControlEvent(event)

        default:
            return true
        }
    }

    func handlePostPersistEvent(_ event: ConversationEvent) {
        guard case .toolResult(let id, _, _, _, _) = event else {
            return
        }
        // Tool output proves the approval prompt is terminal even if the provider replays prompts late.
        resolveUnresolvedToolApprovalsCompletedByToolResult(toolUseId: id)
    }

    func handleProviderSessionMetadataChanged(_ event: ConversationEvent) -> Bool {
        guard case .providerSessionMetadataChanged(_, let name, let preview) = event else {
            return false
        }
        guard let providerTitle = Self.normalizedProviderSessionName(name) ?? Self.normalizedProviderSessionName(preview),
              let dbConversation = dbConversation(),
              let thread = dbConversation.thread,
              !thread.hasCustomName else {
            return true
        }

        let previousThreadDisplayName = thread.displayName()
        let mainConversation = thread.conversations.first { $0.isMain }
        if previousThreadDisplayName != providerTitle {
            thread.name = providerTitle
        }
        if let mainConversation,
           mainConversation.shouldFollowThreadRename(previousThreadDisplayName: previousThreadDisplayName) {
            mainConversation.title = mainConversation.persistedTitle(from: providerTitle)
        }
        return true
    }

    func handlePermissionModeChanged(_ permissionMode: String) -> Bool {
        syncRuntimePermissionMode(permissionMode)
        clearApprovedExitPlanModeApprovalAfterPermissionModeChange(permissionMode)
        return false
    }

    func handleCollaborationModeChanged(_ isPlanModeEnabled: Bool) -> Bool {
        syncRuntimePlanMode(isPlanModeEnabled)
        if !isPlanModeEnabled {
            clearApprovedExitPlanModeApprovalIfNeeded()
        }
        return false
    }

    func shouldSuppressInterruptedTurnFallout(_ event: ConversationEvent) -> Bool {
        guard state.lastTurnInterrupted,
              !state.turnState.isActive else {
            return false
        }
        handleSuppressedPromptApproval(from: event, deferResolution: false)
        switch event {
        case .messageChunk,
             .message,
             .toolCall,
             .toolResult,
             .toolApprovalRequested,
             .toolApprovalFailed,
             .taskListSnapshot,
             .tokens,
             .stop,
             .runtimeActivity:
            state.activeRuntimeActivityTurnId = nil
            state.isAutomaticSessionHandoffPending = false
            state.isCancellingTurn = false
            state.lastTurnError = nil
            state.clearStreamingText()
            state.turnState.endTurn()
            scheduleSave()
            return true
        default:
            return false
        }
    }

    func handleMessageChunk(_ text: String, parentToolUseId: String?) -> Bool {
        if parentToolUseId == nil {
            state.appendStreamingChunk(text)
        }
        return false
    }

    func shouldPersistMessageEvent(role: String, content: String) -> Bool {
        if role == "assistant" {
            state.clearStreamingText()
            if state.pendingSyntheticAssistantDuplicateText == content {
                state.pendingSyntheticAssistantDuplicateText = nil
                return false
            }
            return true
        }
        return false
    }

    func shouldPersistTokensEvent(_ payload: TokenEventPayload) -> Bool {
        shouldPersistTokenEvent(payload)
    }

    func handleSubAgentControlEvent(_ event: ConversationEvent) -> Bool {
        if case .subAgentCompleted = event {
            persistSubAgentCompletionMarker(for: event)
            return false
        }
        state.grouper.handleSubAgentControl(event)
        return false
    }

    func handleTokenEvent(_ payload: TokenEventPayload) -> TokenEventPersistence {
        let hadStreamingText = state.streamingText != nil
        state.clearStreamingText()
        guard payload.stopReason != ConversationEvent.interimUsageStopReason else { return .persistTokens }
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
                state.turnState.endTurn()
                Task { @MainActor [self] in await startSessionHandoff(trigger: .automatic) }
            } else if isAwaitingAutomaticSessionHandoffTurnCompletion(for: payload) {
                // Keep queued messages parked until the real terminal token starts handoff.
            } else {
                handleTurnCompleted()
            }
        } else if didQueueExitPlanModeFollowUp || !payload.permissionDenials.isEmpty {
            handleTurnCompleted()
        } else {
            state.turnState.endTurn()
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
        state.turnState.endTurn()
        return .dropTokens
    }

    func handleRuntimeActivity(
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
            handleRuntimeActivityIdle(turnId: turnId, outcome: outcome)
        }
        return false
    }

    func handleRuntimeActivityIdle(
        turnId: String?,
        outcome: ConversationRuntimeActivityOutcome
    ) {
        guard !shouldIgnoreRuntimeActivityIdle(turnId: turnId) else {
            scheduleSave()
            return
        }

        let didQueueExitPlanModeFollowUp = markPendingExitPlanModeFollowUpReadyAfterRuntimeIdle(
            turnId: turnId,
            outcome: outcome
        )
        state.clearStreamingText()
        switch outcome {
        case .unknown, .completed:
            state.activeRuntimeActivityTurnId = nil
            if state.isCancellingTurn {
                handleRuntimeActivityInterruptedTurn()
            } else {
                handleTurnCompleted()
                scheduleSave()
            }
        case .failed(let message):
            if didQueueExitPlanModeFollowUp {
                handleRuntimeActivityCompletedForPendingExitPlanModeFollowUp()
                return
            }
            handleRuntimeActivityFailedTurn(message: message)
        case .interrupted:
            if didQueueExitPlanModeFollowUp {
                handleRuntimeActivityCompletedForPendingExitPlanModeFollowUp()
                return
            }
            handleRuntimeActivityInterruptedTurn()
        }
    }

    func handleRuntimeActivityCompletedForPendingExitPlanModeFollowUp() {
        state.activeRuntimeActivityTurnId = nil
        state.isAutomaticSessionHandoffPending = false
        state.isCancellingTurn = false
        state.lastTurnInterrupted = false
        state.lastTurnError = nil
        state.turnState.endTurn()
        handleTurnCompleted()
        scheduleSave()
    }

    func handleRuntimeActivityFailedTurn(message: String) {
        state.activeRuntimeActivityTurnId = nil
        state.isAutomaticSessionHandoffPending = false
        state.isCancellingTurn = false
        state.lastTurnInterrupted = false
        state.lastTurnError = normalizedTurnErrorMessage(message, fallback: "Agent turn failed")
        state.turnState.endTurn()
        scheduleSave()
    }

    func handleRuntimeActivityInterruptedTurn() {
        let shouldPersistInterruption = !state.lastTurnInterrupted
        state.activeRuntimeActivityTurnId = nil
        state.isAutomaticSessionHandoffPending = false
        state.isCancellingTurn = false
        state.lastTurnError = nil
        state.lastTurnInterrupted = true
        markTranscriptToolsInterrupted()
        state.turnState.endTurn()
        if shouldPersistInterruption {
            persistSyntheticStopRecord(message: ConversationInterruption.displayMessage)
        }
        scheduleSave()
    }

    func shouldPersistErrorEvent(message: String) -> Bool {
        state.activeRuntimeActivityTurnId = nil
        state.clearStreamingText()
        if shouldSuppressInterruptedError(message) {
            state.isCancellingTurn = false
            state.turnState.endTurn()
            scheduleSave()
            return false
        }

        state.isAutomaticSessionHandoffPending = false
        state.isCancellingTurn = false
        state.lastTurnInterrupted = false
        state.lastTurnError = nil
        state.turnState.endTurn()
        return true
    }

    func shouldSuppressInterruptedError(_ message: String) -> Bool {
        guard state.lastTurnInterrupted, !state.turnState.isActive else {
            return false
        }
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedMessage.contains("interrupt") ||
            normalizedMessage.contains("cancel") ||
            normalizedMessage.contains("no active turn")
    }

    func normalizedTurnErrorMessage(_ message: String, fallback: String) -> String {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedMessage.isEmpty ? fallback : trimmedMessage
    }

    func shouldPersistTokenEvent(_ payload: TokenEventPayload) -> Bool {
        switch handleTokenEvent(payload) {
        case .persistTokens:
            return true
        case .dropTokens:
            scheduleSave()
            return false
        case .persistSyntheticStop(let message):
            persistSyntheticStopRecord(message: message)
            return false
        case .persistSyntheticAssistant(let message):
            persistSyntheticAssistantRecord(message: message)
            return false
        }
    }

    func handleInterruptedTokenTurn() {
        state.activeRuntimeActivityTurnId = nil
        state.isAutomaticSessionHandoffPending = false
        state.isCancellingTurn = false
        state.lastTurnError = nil
        state.lastTurnInterrupted = true
        markTranscriptToolsInterrupted()
        state.turnState.endTurn()
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

    func shouldPersistStopEvent(message: String?) -> Bool {
        state.activeRuntimeActivityTurnId = nil
        state.isAutomaticSessionHandoffPending = false
        if ConversationInterruption.isDisplayMessage(message), state.lastTurnInterrupted {
            state.isCancellingTurn = false
            markTranscriptToolsInterrupted()
            state.turnState.endTurn()
            scheduleSave()
            return false
        }
        if state.isCancellingTurn || ConversationInterruption.isDisplayMessage(message) {
            state.isCancellingTurn = false
            state.lastTurnError = nil
            state.lastTurnInterrupted = true
            markTranscriptToolsInterrupted()
        }
        state.turnState.endTurn()
        return true
    }

    func persistSyntheticStopRecord(message: String) {
        guard let dbConversation = dbConversation(),
              let record = ConversationEvent.stop(message: message).toRecord(conversation: dbConversation) else {
            return
        }

        modelContext.insert(record)
        state.grouper.append(event: record)
        scheduleSave()
    }

    func persistSyntheticAssistantRecord(message: String) {
        guard let dbConversation = dbConversation(),
              let record = ConversationEvent.message(role: "assistant", content: message, parentToolUseId: nil)
                .toRecord(conversation: dbConversation) else {
            return
        }

        modelContext.insert(record)
        state.grouper.append(event: record)
        scheduleSave()
    }

    func persistEventRecord(for event: ConversationEvent) {
        guard let dbConversation = dbConversation(),
              let record = event.toRecord(conversation: dbConversation) else {
            return
        }

        modelContext.insert(record)
        state.grouper.append(event: record)
        scheduleContextWindowCacheUpdateIfNeeded(from: record)
        scheduleSave()
    }

    func shouldSuppressTokenErrorComposerMessage(_ payload: TokenEventPayload) -> Bool {
        if state.grouper.items.containsCurrentTurnTranscriptError {
            return true
        }
        return ConversationErrorDisplayPolicy.isGenericStopReason(payload.stopReason) &&
            state.grouper.items.containsCurrentTurnAssistantMessage
    }
}

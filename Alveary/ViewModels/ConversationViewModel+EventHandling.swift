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
        if state.isGeneratingCommitMessage { return shouldPersistHiddenCommitMessageGenerationEvent(event) }
        if state.isHandingOffSession || state.failedSessionHandoffMessage != nil { return shouldPersistHiddenSessionHandoffEvent(event) }
        if state.isDrainingCommitMessageGenerationEvents { return acknowledgeLateHiddenCommitMessageGenerationEvent(event) }

        if shouldSuppressPromptDismissalEvent(event) || shouldSuppressPromptDismissalFallout(event) {
            return false
        }

        if shouldSuppressInterruptedTurnFallout(event) { return false }

        switch event {
        case .sessionInit, .providerSessionMetadataChanged: return false

        case .permissionModeChanged(let permissionMode):
            return handlePermissionModeChanged(permissionMode)

        case .collaborationModeChanged(let isPlanModeEnabled):
            return handleCollaborationModeChanged(isPlanModeEnabled)

        case .toolCall(_, let name, _, _, _):
            return shouldPersistToolCallEvent(event, toolName: name)
        case .toolResult(let id, _, let isError, _, _):
            return shouldPersistToolResultEvent(toolUseId: id, isError: isError)
        case .messageChunk(let text, let parentToolUseId):
            return handleMessageChunk(text, parentToolUseId: parentToolUseId)
        case .thinking(let content, let parentToolUseId):
            return handleThinking(content, parentToolUseId: parentToolUseId)

        case .message(let role, let content, _):
            return shouldPersistMessageEvent(role: role, content: content)

        case .runtimeUserMessage:
            return shouldPersistRuntimeUserMessageEvent()

        case .steeredConversation(let inputID): return shouldPersistSteeredConversation(inputID: inputID)
        case .tokens:
            return shouldPersistTokensEvent(event)

        case .contextCompactionStarted, .contextCompactionCompleted, .contextCompactionFailed:
            return shouldPersistContextCompactionEvent()

        case .goal(let event): return handleGoalEvent(event)
        case .toolApprovalRequested(let approval):
            return shouldPersistToolApprovalRequestedEvent(approval)

        case .toolApprovalFailed(let failure):
            return shouldPersistToolApprovalFailedEvent(failure)

        case .runtimeActivity(let activityState, let turnId, let outcome):
            return handleRuntimeActivity(state: activityState, turnId: turnId, outcome: outcome)

        case .stop(let message):
            state.clearStreamingText()
            return shouldPersistStopEvent(message: message)

        case .error(let message):
            return shouldPersistErrorEvent(message: message)

        case .subAgentStarted, .subAgentProgress, .subAgentCompleted:
            return shouldPersistSubAgentControlEvent(event)
        case .taskListSnapshot:
            return shouldPersistTaskListSnapshotEvent()

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
        let appShotTitleFallback = state.appShotProviderSessionTitleFallback ??
            latestPersistedAppShotProviderSessionTitleFallback()
        guard let providerTitle = Self.providerSessionTitle(
            name: name,
            preview: preview,
            appShotTitleFallback: appShotTitleFallback
        ),
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

    func latestPersistedAppShotProviderSessionTitleFallback() -> String? {
        conversationEventRecords().reversed().first { record in
            record.type == "message" &&
                record.role == "user" &&
                record.persistedImageAttachments.contains(where: \.isStoredAppShotScreenshot)
        }.map {
            Self.appShotThreadPreviewTitle(fromVisibleUserInput: $0.content ?? "")
        }
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

    func shouldPersistToolCallEvent(_ event: ConversationEvent, toolName: String) -> Bool {
        state.clearThoughtText()
        clearApprovedExitPlanModeApprovalAfterImplementationToolCall(toolName: toolName)
        return !persistSubAgentStartIfNeeded(for: event)
    }

    func shouldPersistToolResultEvent(toolUseId: String, isError: Bool) -> Bool {
        state.clearThoughtText()
        clearApprovedExitPlanModeApprovalAfterToolResult(toolUseId: toolUseId, isError: isError)
        return true
    }

    func shouldPersistToolApprovalRequestedEvent(_ approval: ToolApprovalRequest) -> Bool {
        state.clearThoughtText()
        return handleToolApprovalRequested(approval)
    }

    func shouldPersistToolApprovalFailedEvent(_ failure: ToolApprovalFailure) -> Bool {
        state.clearThoughtText()
        return handleToolApprovalFailed(failure)
    }

    func shouldPersistSubAgentControlEvent(_ event: ConversationEvent) -> Bool {
        state.clearThoughtText()
        return handleSubAgentControlEvent(event)
    }

    func shouldPersistTaskListSnapshotEvent() -> Bool {
        state.clearThoughtText()
        return true
    }

    func shouldPersistContextCompactionEvent() -> Bool {
        state.clearStreamingText()
        return true
    }

    func shouldSuppressInterruptedTurnFallout(_ event: ConversationEvent) -> Bool {
        guard state.lastTurnInterrupted,
              !state.turnState.isActive else {
            return false
        }
        handleSuppressedPromptApproval(from: event, deferResolution: false)
        switch event {
        case .messageChunk,
             .thinking,
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
            state.endTurn()
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

    func handleThinking(_ content: String, parentToolUseId: String?) -> Bool {
        guard parentToolUseId == nil,
              state.streamingText == nil else {
            return false
        }
        state.appendThoughtChunk(content)
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

    func shouldPersistRuntimeUserMessageEvent() -> Bool {
        state.clearThoughtText()
        return true
    }

    func shouldPersistTokensEvent(_ event: ConversationEvent) -> Bool {
        guard let payload = TokenEventPayload(event) else { return true }
        return shouldPersistTokensEvent(payload)
    }

    func shouldPersistTokensEvent(_ payload: TokenEventPayload) -> Bool {
        shouldPersistTokenEvent(payload)
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

    func handleSubAgentControlEvent(_ event: ConversationEvent) -> Bool {
        if case .subAgentCompleted = event {
            persistSubAgentCompletionMarker(for: event)
            return false
        }
        state.grouper.handleSubAgentControl(event)
        return false
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
        state.endTurn()
        handleTurnCompleted()
        scheduleSave()
    }

    func handleRuntimeActivityFailedTurn(message: String) {
        state.activeRuntimeActivityTurnId = nil
        state.isAutomaticSessionHandoffPending = false
        state.isCancellingTurn = false
        state.lastTurnInterrupted = false
        state.lastTurnError = normalizedTurnErrorMessage(message, fallback: "Agent turn failed")
        state.endTurn()
        scheduleSave()
    }

    func handleRuntimeActivityInterruptedTurn() {
        let shouldPersistInterruption = !state.lastTurnInterrupted
        state.activeRuntimeActivityTurnId = nil
        state.isAutomaticSessionHandoffPending = false
        state.isCancellingTurn = false
        state.lastTurnError = nil
        state.lastTurnInterrupted = true
        markTranscriptActivityInterrupted()
        state.endTurn()
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
            state.endTurn()
            scheduleSave()
            return false
        }

        state.isAutomaticSessionHandoffPending = false
        state.isCancellingTurn = false
        state.lastTurnInterrupted = false
        state.lastTurnError = nil
        state.endTurn()
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

    func shouldPersistStopEvent(message: String?) -> Bool {
        state.activeRuntimeActivityTurnId = nil
        state.isAutomaticSessionHandoffPending = false
        if ConversationInterruption.isDisplayMessage(message), state.lastTurnInterrupted {
            state.isCancellingTurn = false
            markTranscriptActivityInterrupted()
            state.endTurn()
            scheduleSave()
            return false
        }
        if state.isCancellingTurn || ConversationInterruption.isDisplayMessage(message) {
            state.isCancellingTurn = false
            state.lastTurnError = nil
            state.lastTurnInterrupted = true
            markTranscriptActivityInterrupted()
        }
        state.endTurn()
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

}

private extension LocalImageAttachment {
    var isStoredAppShotScreenshot: Bool {
        fileURL.deletingLastPathComponent().lastPathComponent == "appshots"
    }
}

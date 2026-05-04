extension ConversationViewModel {
    func handleEvent(_ event: ConversationEvent) {
        guard shouldPersistEvent(event) else {
            return
        }
        persistEventRecord(for: event)
    }
}

private extension ConversationViewModel {
    // swiftlint:disable:next cyclomatic_complexity
    func shouldPersistEvent(_ event: ConversationEvent) -> Bool {
        if state.isHandingOffSession || state.failedSessionHandoffMessage != nil {
            return shouldPersistHiddenSessionHandoffEvent(event)
        }

        switch event {
        case .sessionInit:
            return false

        case .permissionModeChanged(let permissionMode):
            return handlePermissionModeChanged(permissionMode)

        case .toolResult(let id, _, let isError, _, _):
            clearApprovedExitPlanModeApprovalAfterToolResult(toolUseId: id, isError: isError)
            return true

        case .messageChunk(let text, let parentToolUseId):
            return handleMessageChunk(text, parentToolUseId: parentToolUseId)

        case .message(let role, _, _):
            return shouldPersistMessageEvent(role: role)

        case .tokens:
            guard let payload = TokenEventPayload(event) else { return true }
            return shouldPersistTokensEvent(payload)

        case .toolApprovalRequested(let approval):
            return handleToolApprovalRequested(approval)

        case .toolApprovalFailed(let failure):
            return handleToolApprovalFailed(failure)

        case .stop(let message):
            return shouldPersistStopEvent(message: message)

        case .subAgentStarted, .subAgentProgress, .subAgentCompleted:
            return handleSubAgentControlEvent(event)

        default:
            return true
        }
    }

    func handlePermissionModeChanged(_ permissionMode: String) -> Bool {
        syncRuntimePermissionMode(permissionMode)
        clearApprovedExitPlanModeApprovalAfterPermissionModeChange(permissionMode)
        return false
    }

    func handleMessageChunk(_ text: String, parentToolUseId: String?) -> Bool {
        if parentToolUseId == nil {
            state.appendStreamingChunk(text)
        }
        return false
    }

    func shouldPersistMessageEvent(role: String) -> Bool {
        if role == "assistant" {
            state.clearStreamingText()
            return true
        }
        return false
    }

    func shouldPersistTokensEvent(_ payload: TokenEventPayload) -> Bool {
        shouldPersistTokenEvent(payload)
    }

    func handleSubAgentControlEvent(_ event: ConversationEvent) -> Bool {
        state.grouper.handleSubAgentControl(event)
        return false
    }

    func handleTokenEvent(_ payload: TokenEventPayload) -> TokenEventPersistence {
        let hadStreamingText = state.streamingText != nil
        state.clearStreamingText()
        guard payload.stopReason != ConversationEvent.interimUsageStopReason else { return .persistTokens }
        guard !handleToolDeferredTokenIfNeeded(payload) else { return .persistTokens }
        clearResolvedPendingToolApprovalIfNeeded()

        if let slashCommandNotice = state.synthesizedSlashCommandFailureNotice(
            for: payload,
            hadStreamingText: hadStreamingText
        ) {
            state.isCancellingTurn = false
            state.lastTurnInterrupted = false
            state.lastTurnError = nil
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

        if state.lastTurnInterrupted, payload.isError, payload.permissionDenials.isEmpty {
            state.isCancellingTurn = false
            state.lastTurnError = nil
            state.turnState.endTurn()
            return .dropTokens
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
        } else if !payload.permissionDenials.isEmpty { // Permission denials end the provider turn; drain queued follow-up.
            handleTurnCompleted()
        } else {
            state.turnState.endTurn()
        }

        return .persistTokens
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
        state.isAutomaticSessionHandoffPending = false
        state.isCancellingTurn = false
        state.lastTurnError = nil
        state.lastTurnInterrupted = true
        state.turnState.endTurn()
    }

    func handleFailedTokenTurn(_ payload: TokenEventPayload) {
        state.isAutomaticSessionHandoffPending = false
        state.lastTurnInterrupted = false
        state.lastTurnError = payload.permissionDenials.isEmpty ? payload.stopReason ?? "Agent turn failed" : nil
    }

    func shouldPersistStopEvent(message: String?) -> Bool {
        state.isAutomaticSessionHandoffPending = false
        if state.isCancellingTurn || ConversationInterruption.isDisplayMessage(message) {
            state.isCancellingTurn = false
            state.lastTurnError = nil
            state.lastTurnInterrupted = true
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
}

import Foundation

extension ConversationViewModel {
    func handleTurnCompleted() {
        state.turnState.endTurn()
        scheduleQueueDrainIfNeeded()
    }

    func sendReserved(
        _ message: String,
        stagedContextOverride: String? = nil,
        useCurrentStagedContextWhenOverrideNil: Bool = true,
        existingLocalUserMessageID: String? = nil
    ) async throws {
        let appliedContext = stagedContextOverride ?? (useCurrentStagedContextWhenOverrideNil ? state.stagedContext : nil)
        let transportMessage = buildTransportMessage(
            message: message,
            stagedContext: appliedContext
        )

        guard let dbConversation = dbConversation() else {
            throw AgentError.spawnFailed("Conversation no longer exists")
        }

        state.lastTurnInterrupted = false
        state.isCancellingTurn = false
        state.activeRuntimeActivityTurnId = nil
        state.pendingSyntheticAssistantDuplicateText = nil
        (state.lastTurnError, state.failedSessionHandoffMessage) = (nil, nil)
        try await sendVisibleAgentMessage(transportMessage)
        if useCurrentStagedContextWhenOverrideNil && stagedContextOverride == nil {
            state.stagedContext = nil
        }
        clearConsumedPendingRestoreContext(using: appliedContext)
        markVisibleTurnStarted()
        state.turnState.beginTurn()
        if let existingLocalUserMessageID {
            state.clearRetryableFailedMessage(id: existingLocalUserMessageID)
        } else {
            insertLocalUserMessage(message, into: dbConversation)
        }
    }

    func buildTransportMessage(
        message: String,
        stagedContext: String?
    ) -> String {
        if let context = stagedContext {
            return context + "\n\n" + message
        }
        return message
    }

    func sendVisibleAgentMessage(_ message: String) async throws {
        let markedPromptDismissalReplacement = markPromptDismissalNewOutboundTurnStarted()
        do {
            try await agentsManager.sendMessage(message, conversationId: conversation.id)
        } catch {
            restorePromptDismissalNewOutboundTurnStartedIfNeeded(markedPromptDismissalReplacement)
            throw error
        }
    }

    func steerQueuedMessage(id: UUID) async throws {
        guard canSteerCurrentTurn else {
            throw AgentError.spawnFailed("Wait for the agent to be actively working before steering")
        }
        guard state.inFlightQueuedMessageID == nil else {
            throw AgentError.spawnFailed("Wait for the current queued message action to finish")
        }
        let queuedMessage = try queuedMessageForSteering(id: id)

        var localMessageID: String?
        state.inFlightQueuedMessageID = id
        defer {
            if state.inFlightQueuedMessageID == id {
                state.inFlightQueuedMessageID = nil
            }
        }

        do {
            try await withOutboundReservation {
                guard let queuedMessage = state.messageQueue.remove(id: id),
                      let dbConversation = dbConversation() else {
                    throw AgentError.spawnFailed("Conversation no longer exists")
                }

                let transportMessage = buildTransportMessage(
                    message: queuedMessage.text,
                    stagedContext: queuedMessage.stagedContext
                )
                let localMessage = insertLocalUserMessage(
                    queuedMessage.text,
                    into: dbConversation
                )
                localMessageID = localMessage.id

                state.lastTurnInterrupted = false
                state.isCancellingTurn = false
                state.lastTurnError = nil
                state.activeRuntimeActivityTurnId = nil
                try await sendVisibleAgentMessage(transportMessage)
                markVisibleTurnStarted()
                state.turnState.beginTurn()
                clearConsumedPendingRestoreContext(using: queuedMessage.stagedContext)
                state.clearRetryableFailedMessage(id: localMessage.id)
                state.respawnAttempts = 0
            }
        } catch {
            if let localMessageID {
                state.markRetryableFailedMessage(id: localMessageID, stagedContext: queuedMessage.stagedContext)
            }
            state.lastTurnError = "Steer failed: \(error.localizedDescription)"
            throw error
        }
    }
}

extension ConversationViewModel {
    func scheduleQueueDrainIfNeeded() {
        scheduleQueueDrainIfNeeded(allowInactiveBeforeFirstActivation: false, allowInitialSetup: false)
    }

    func scheduleExitPlanModeFollowUpDrainIfNeeded() {
        // Denied-plan follow-ups may be staged before the view ever activates, but
        // explicit deactivation must still keep them parked until the view returns.
        scheduleQueueDrainIfNeeded(allowInactiveBeforeFirstActivation: true, allowInitialSetup: true)
    }

    private func scheduleQueueDrainIfNeeded(
        allowInactiveBeforeFirstActivation: Bool,
        allowInitialSetup: Bool
    ) {
        guard queueDrainTask == nil,
              state.messageQueue.peekNext() != nil,
              !state.turnState.isActive,
              canDrainForCurrentLifecycle(allowInactiveBeforeFirstActivation: allowInactiveBeforeFirstActivation) else {
            return
        }

        queueDrainTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer { self.queueDrainTask = nil }
            await self.drainNextQueuedMessageIfReady(
                allowInactiveBeforeFirstActivation: allowInactiveBeforeFirstActivation,
                allowInitialSetup: allowInitialSetup
            )
        }
    }
}

private extension ConversationViewModel {
    func drainNextQueuedMessageIfReady(
        allowInactiveBeforeFirstActivation: Bool = false,
        allowInitialSetup: Bool = false
    ) async {
        guard canDrainNextQueuedMessageLocally(
            allowInactiveBeforeFirstActivation: allowInactiveBeforeFirstActivation,
            allowInitialSetup: allowInitialSetup
        ) else {
            return
        }

        let runtimeStatus = await runtimeStatusForQueueDrain()
        guard !Task.isCancelled,
              canDrainNextQueuedMessageLocally(
                  allowInactiveBeforeFirstActivation: allowInactiveBeforeFirstActivation,
                  allowInitialSetup: allowInitialSetup
              ) else {
            return
        }
        guard runtimeStatus == .idle || runtimeStatus == .neutral || runtimeStatus == .stopped else {
            return
        }
        guard let next = state.messageQueue.peekNext(),
              let dbConversation = dbConversation() else {
            return
        }

        state.inFlightQueuedMessageID = next.id
        defer {
            if state.inFlightQueuedMessageID == next.id {
                state.inFlightQueuedMessageID = nil
            }
        }

        do {
            try await sendNextQueuedMessage(next, in: dbConversation)
        } catch {
            state.lastTurnError = "Queued message failed to send: \(error.localizedDescription)"
            state.turnState.endTurn()
        }
    }

    func canDrainNextQueuedMessageLocally(
        allowInactiveBeforeFirstActivation: Bool = false,
        allowInitialSetup: Bool = false
    ) -> Bool {
        canDrainForCurrentLifecycle(allowInactiveBeforeFirstActivation: allowInactiveBeforeFirstActivation) &&
            (!needsSetup || allowInitialSetup) &&
            initialSetupTask == nil &&
            state.setupPhase == nil &&
            !state.isCancellingInitialSetup &&
            !state.isSendingMessage &&
            !state.turnState.isActive &&
            state.inFlightQueuedMessageID == nil &&
            state.pendingToolApproval == nil &&
            !hasUnansweredPrompt &&
            state.pendingExitPlanModeFollowUp == nil &&
            !state.hasActiveSessionHandoff &&
            !state.isAutomaticSessionHandoffPending &&
            !state.isCancellingTurn &&
            !state.lastTurnInterrupted &&
            state.lastTurnError == nil &&
            state.failedSessionHandoffMessage == nil &&
            !state.isReconfiguringSession
    }

    func canDrainForCurrentLifecycle(allowInactiveBeforeFirstActivation: Bool) -> Bool {
        hasActivatedViewLifecycle || (allowInactiveBeforeFirstActivation && !hasEverActivatedViewLifecycle)
    }

    func runtimeStatusForQueueDrain() async -> ActivitySignal {
        let cachedStatus = agentsManager.status(for: conversation.id)
        guard cachedStatus == .busy,
              !state.turnState.isActive,
              state.messageQueue.peekNext() != nil else {
            return cachedStatus
        }
        return await agentsManager.refreshStatus(conversationId: conversation.id)
    }

    func queuedMessageForSteering(id: UUID) throws -> QueuedMessage {
        guard let queuedMessage = state.messageQueue.pending.first(where: { $0.id == id }) else {
            throw AgentError.spawnFailed("That queued message is no longer available")
        }
        guard queuedMessage.requiredPlanModeEnabled == nil else {
            throw AgentError.spawnFailed("Plan-mode queued messages send on the next turn")
        }
        guard queuedMessage.requiredSpeedMode == nil else {
            throw AgentError.spawnFailed("Speed-mode queued messages send on the next turn")
        }
        return queuedMessage
    }

    func sendNextQueuedMessage(_ next: QueuedMessage, in dbConversation: Conversation) async throws {
        var localMessageID: String?

        if let requiredPlanModeEnabled = next.requiredPlanModeEnabled {
            try await ensurePlanModeForOutbound(requiredPlanModeEnabled)
        }
        if let requiredSpeedMode = next.requiredSpeedMode {
            try await ensureSpeedModeForOutbound(requiredSpeedMode)
        }
        try await applyPendingSessionSettingsBeforeNextOutboundTurn()
        try await withOutboundReservation {
            guard try await prepareRuntimeForQueuedMessage() else {
                return
            }

            guard let queuedMessage = state.messageQueue.remove(id: next.id) else {
                state.turnState.endTurn()
                return
            }

            let localMessage = insertLocalUserMessage(
                queuedMessage.text,
                into: dbConversation
            )
            localMessageID = localMessage.id

            do {
                try await deliverMessageReserved(
                    queuedMessage.text,
                    stagedContextOverride: queuedMessage.stagedContext,
                    useCurrentStagedContextWhenOverrideNil: false,
                    existingLocalUserMessageID: localMessage.id,
                    respawnSettingsSource: .currentContinuation
                )
                state.respawnAttempts = 0
            } catch {
                if let localMessageID {
                    state.markRetryableFailedMessage(
                        id: localMessageID,
                        stagedContext: queuedMessage.stagedContext
                    )
                }
                throw error
            }
        }
    }

    func prepareRuntimeForQueuedMessage() async throws -> Bool {
        switch await agentsManager.outboundReadiness(conversationId: conversation.id) {
        case .ready:
            return true
        case .respawnRequired:
            guard state.respawnAttempts < Self.maxRespawnAttempts else {
                state.lastTurnError = "Agent process keeps crashing — queued message paused"
                state.respawnAttempts = 0
                state.turnState.endTurn()
                return false
            }
            state.respawnAttempts += 1
            try await startAgentReserved(config: makeSpawnConfig(settingsSource: .currentContinuation))
            return true
        case .blocked(let reason):
            throw AgentError.spawnFailed(reason)
        }
    }

}

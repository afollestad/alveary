import Foundation

extension ConversationViewModel {
    func handleTurnCompleted() {
        guard state.pendingToolApproval == nil else {
            state.turnState.endTurn()
            return
        }

        guard !state.isAwaitingExitPlanModeFollowUp else {
            state.turnState.endTurn()
            return
        }

        guard state.messageQueue.peekNext() != nil else {
            state.turnState.endTurn()
            return
        }

        Task { @MainActor in
            guard state.inFlightQueuedMessageID == nil else {
                return
            }
            guard let next = state.messageQueue.peekNext() else {
                state.turnState.endTurn()
                return
            }
            guard let dbConversation = dbConversation() else {
                state.turnState.endTurn()
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
        (state.lastTurnError, state.failedSessionHandoffMessage) = (nil, nil)
        try await agentsManager.sendMessage(transportMessage, conversationId: conversation.id)
        if useCurrentStagedContextWhenOverrideNil && stagedContextOverride == nil {
            state.stagedContext = nil
        }
        clearConsumedPendingRestoreContext(using: appliedContext)
        state.turnState.beginTurn()
        if let existingLocalUserMessageID {
            state.clearRetryableFailedMessage(id: existingLocalUserMessageID)
        } else {
            insertLocalUserMessage(message, into: dbConversation, shouldAutoNameThread: true)
        }
    }

    func steerQueuedMessage(id: UUID) async throws {
        guard isAgentActivelyWorking else {
            throw AgentError.spawnFailed("Wait for the agent to be actively working before steering")
        }
        guard state.inFlightQueuedMessageID == nil else {
            throw AgentError.spawnFailed("Wait for the current queued message action to finish")
        }
        guard let queuedMessage = state.messageQueue.pending.first(where: { $0.id == id }) else {
            throw AgentError.spawnFailed("That queued message is no longer available")
        }

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
                    into: dbConversation,
                    shouldAutoNameThread: false
                )
                localMessageID = localMessage.id

                state.lastTurnInterrupted = false
                state.isCancellingTurn = false
                state.lastTurnError = nil
                state.activeRuntimeActivityTurnId = nil
                try await agentsManager.sendMessage(transportMessage, conversationId: conversation.id)
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

private extension ConversationViewModel {
    func sendNextQueuedMessage(_ next: QueuedMessage, in dbConversation: Conversation) async throws {
        var localMessageID: String?

        try await applyPendingSessionSettingsBeforeNextOutboundTurn()
        try await withOutboundReservation {
            if await needsRespawn() {
                guard state.respawnAttempts < Self.maxRespawnAttempts else {
                    state.lastTurnError = "Agent process keeps crashing — queued message paused"
                    state.respawnAttempts = 0
                    state.turnState.endTurn()
                    return
                }
                state.respawnAttempts += 1
            }

            guard let queuedMessage = state.messageQueue.remove(id: next.id) else {
                state.turnState.endTurn()
                return
            }

            let localMessage = insertLocalUserMessage(
                queuedMessage.text,
                into: dbConversation,
                shouldAutoNameThread: true
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

    func buildTransportMessage(
        message: String,
        stagedContext: String?
    ) -> String {
        if let context = stagedContext {
            return context + "\n\n" + message
        }
        return message
    }
}

import Foundation

private struct ConversationSaveSnapshot {
    let observedIndex: Int
    let generation: UUID?
    let taskID: UUID
    let delay: Duration
}

extension ConversationViewModel {
    func subscribe() {
        subscriptionTask?.cancel()
        let token = UUID()
        state.activeSubscriptionToken = token
        subscriptionTask = Task { @MainActor in
            guard let subscription = await agentsManager.subscribe(
                conversationId: conversation.id,
                afterIndex: state.lastPersistedEventIndex
            ) else {
                guard state.activeSubscriptionToken == token else {
                    return
                }
                state.activeBufferGeneration = nil
                return
            }

            guard state.activeSubscriptionToken == token else {
                return
            }
            state.activeBufferGeneration = subscription.generation

            for await event in subscription.stream {
                guard state.activeSubscriptionToken == token else {
                    return
                }
                state.lastObservedEventIndex += 1
                handleEvent(event)
            }

            guard !Task.isCancelled, state.activeSubscriptionToken == token else {
                return
            }
            state.turnState.endTurn()
            state.clearStreamingText()
        }
    }

    func handleTurnCompleted() {
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

    @discardableResult
    func insertLocalUserMessage(
        _ message: String,
        into dbConversation: Conversation,
        shouldAutoNameThread: Bool
    ) -> ConversationEventRecord {
        let record = ConversationEventRecord(
            conversationId: dbConversation.id,
            type: "message",
            role: "user",
            content: message,
            conversation: dbConversation
        )
        modelContext.insert(record)
        state.grouper.appendLocalUserMessage(id: record.id, text: message)

        if settingsService.current.autoGenerateNames,
           dbConversation.customTitle == nil,
           let name = Self.threadName(from: message) {
            dbConversation.title = name
        }

        if shouldAutoNameThread,
           settingsService.current.autoGenerateNames,
           let thread = dbConversation.thread,
           thread.isEffectivelyUntitled,
           let name = Self.threadName(from: message) {
            thread.name = name
        }

        scheduleSave()
        return record
    }

    func sendReserved(
        _ message: String,
        stagedContextOverride: String? = nil,
        existingLocalUserMessageID: String? = nil
    ) async throws {
        let appliedContext = stagedContextOverride ?? state.stagedContext
        let transportMessage = buildTransportMessage(
            message: message,
            stagedContext: appliedContext
        )

        guard let dbConversation = dbConversation() else {
            throw AgentError.spawnFailed("Conversation no longer exists")
        }

        state.lastTurnError = nil
        try await agentsManager.sendMessage(transportMessage, conversationId: conversation.id)
        if stagedContextOverride == nil {
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
        guard state.turnState.isActive else {
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

                state.lastTurnError = nil
                try await agentsManager.sendMessage(transportMessage, conversationId: conversation.id)
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

    func handleEvent(_ event: ConversationEvent) {
        guard shouldPersistEvent(event) else {
            return
        }
        persistEventRecord(for: event)
    }

    func scheduleSave() {
        guard saveTask == nil else {
            needsFollowUpSave = true
            return
        }

        let snapshot = ConversationSaveSnapshot(
            observedIndex: state.lastObservedEventIndex,
            generation: state.activeBufferGeneration,
            taskID: UUID(),
            delay: .milliseconds(state.turnState.isActive ? 350 : 150)
        )
        saveTaskID = snapshot.taskID
        saveTask = Task { @MainActor [snapshot] in
            await performScheduledSave(snapshot)
        }
    }

    func flushPendingSaveIfNeeded() async {
        guard let saveTask else {
            return
        }
        await saveTask.value
    }

    func hydratePendingRestoreContextIfNeeded() {
        guard let pendingRestoreContext = dbConversation()?.pendingRestoreContext else {
            return
        }

        if state.stagedContext == pendingRestoreContext {
            return
        }

        guard !state.messageQueue.pending.contains(where: { $0.stagedContext == pendingRestoreContext }) else {
            return
        }

        state.stagedContext = pendingRestoreContext
    }
}

private extension ConversationViewModel {
    func sendNextQueuedMessage(_ next: QueuedMessage, in dbConversation: Conversation) async throws {
        var localMessageID: String?

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
                    existingLocalUserMessageID: localMessage.id
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

    func clearConsumedPendingRestoreContext(using stagedContext: String?) {
        guard let stagedContext,
              let dbConversation = dbConversation(),
              dbConversation.pendingRestoreContext == stagedContext else {
            return
        }

        dbConversation.pendingRestoreContext = nil
        do {
            try modelContext.save()
        } catch {
            // Best-effort only; the next save will retry persisting the cleared restore context.
        }
    }

    func shouldPersistEvent(_ event: ConversationEvent) -> Bool {
        switch event {
        case .messageChunk(let text, let parentToolUseId):
            if parentToolUseId == nil {
                state.appendStreamingChunk(text)
            }
            return false

        case .message(let role, _, _) where role == "user":
            return false

        case .message(let role, _, _) where role == "assistant":
            state.clearStreamingText()
            return true

        case .tokens(_, _, _, let isError, let stopReason, _, _, let permissionDenials):
            handleTokenEvent(
                isError: isError,
                stopReason: stopReason,
                permissionDenials: permissionDenials
            )
            return true

        case .stop:
            state.turnState.endTurn()
            return true

        case .subAgentStarted, .subAgentProgress, .subAgentCompleted:
            state.grouper.handleSubAgentControl(event)
            return false

        default:
            return true
        }
    }

    func handleTokenEvent(
        isError: Bool,
        stopReason: String?,
        permissionDenials: [PermissionDenialSummary]
    ) {
        state.clearStreamingText()
        if isError {
            state.lastTurnError = stopReason ?? "Agent turn failed"
        }
        state.lastPermissionDeniedToolNames = Set(permissionDenials.map(\.toolName))
        state.showPermissionBanner = !permissionDenials.isEmpty

        if !isError && permissionDenials.isEmpty {
            handleTurnCompleted()
        } else {
            state.turnState.endTurn()
        }
    }

    func persistEventRecord(for event: ConversationEvent) {
        guard let dbConversation = dbConversation(),
              let record = event.toRecord(conversation: dbConversation) else {
            return
        }

        modelContext.insert(record)
        scheduleSave()
    }

    func performScheduledSave(_ snapshot: ConversationSaveSnapshot) async {
        guard await waitForScheduledSave(snapshot) else {
            return
        }

        await persistScheduledSave(snapshot)
        finishScheduledSave(taskID: snapshot.taskID)
    }

    func waitForScheduledSave(_ snapshot: ConversationSaveSnapshot) async -> Bool {
        do {
            try await Task.sleep(for: snapshot.delay)
            try Task.checkCancellation()
            return true
        } catch {
            finishScheduledSave(taskID: snapshot.taskID)
            return false
        }
    }

    func persistScheduledSave(_ snapshot: ConversationSaveSnapshot) async {
        do {
            try modelContext.save()
        } catch {
            // Keep the older persisted cursor so reconnects replay the unsaved tail.
            return
        }

        guard state.activeBufferGeneration == snapshot.generation, !Task.isCancelled else {
            return
        }

        state.lastPersistedEventIndex = max(state.lastPersistedEventIndex, snapshot.observedIndex)
        if let generation = snapshot.generation {
            await agentsManager.markPersisted(
                conversationId: conversation.id,
                generation: generation,
                upTo: snapshot.observedIndex
            )
        }
    }

    func finishScheduledSave(taskID: UUID) {
        guard saveTaskID == taskID else {
            return
        }

        saveTask = nil
        saveTaskID = nil
        guard needsFollowUpSave else {
            return
        }

        needsFollowUpSave = false
        scheduleSave()
    }
}

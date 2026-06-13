import Foundation

private let streamingChunkBatchEventThreshold = 8
private let streamingChunkBatchCharacterThreshold = 160

private struct SubscriptionChunkBuffer {
    var text = ""
    var eventCount = 0
    var hasPublishedRootChunk = false

    var shouldFlush: Bool {
        eventCount >= streamingChunkBatchEventThreshold || text.count >= streamingChunkBatchCharacterThreshold
    }

    mutating func append(_ chunk: String) {
        text.append(chunk)
        eventCount += 1
    }

    mutating func markImmediatePublish() {
        hasPublishedRootChunk = true
    }

    mutating func resetPublishedState() {
        hasPublishedRootChunk = false
    }

    mutating func takePending() -> (text: String, eventCount: Int)? {
        guard !text.isEmpty else {
            return nil
        }

        let pending = (text, eventCount)
        text = ""
        eventCount = 0
        hasPublishedRootChunk = true
        return pending
    }
}

extension ConversationViewModel {
    func subscribe() {
        subscriptionTask?.cancel()

        let token = UUID()
        state.activeSubscriptionToken = token

        let conversationId = conversation.id
        let afterIndex = state.lastPersistedEventIndex
        let agentsManager = self.agentsManager

        subscriptionTask = Task { [weak self] in
            await self?.runSubscription(
                token: token,
                conversationId: conversationId,
                afterIndex: afterIndex,
                agentsManager: agentsManager
            )
        }
    }
}

private extension ConversationViewModel {
    nonisolated func runSubscription(
        token: UUID,
        conversationId: String,
        afterIndex: Int,
        agentsManager: any AgentsManager
    ) async {
        guard let subscription = await agentsManager.subscribe(
            conversationId: conversationId,
            afterIndex: afterIndex
        ) else {
            await clearSubscriptionGeneration(token: token)
            return
        }

        guard await publishSubscriptionGeneration(subscription.generation, token: token) else {
            return
        }

        var chunkBuffer = SubscriptionChunkBuffer()

        for await event in subscription.stream {
            guard await processSubscriptionEvent(
                event,
                chunkBuffer: &chunkBuffer,
                token: token
            ) else {
                return
            }
        }

        guard await flushSubscriptionChunkBuffer(&chunkBuffer, token: token) else {
            return
        }
        await finishSubscription(token: token)
    }

    nonisolated func publishSubscriptionGeneration(_ generation: UUID, token: UUID) async -> Bool {
        await MainActor.run { [weak self] in
            guard let self,
                  self.state.activeSubscriptionToken == token else {
                return false
            }

            self.state.activeBufferGeneration = generation
            return true
        }
    }

    nonisolated func clearSubscriptionGeneration(token: UUID) async {
        await MainActor.run { [weak self] in
            guard let self,
                  self.state.activeSubscriptionToken == token else {
                return
            }

            self.state.activeBufferGeneration = nil
        }
    }

    nonisolated func handleImmediateSubscriptionEvent(_ event: ConversationEvent, token: UUID) async -> Bool {
        await MainActor.run { [weak self] in
            guard let self,
                  self.state.activeSubscriptionToken == token else {
                return false
            }

            self.state.lastObservedEventIndex += 1
            self.handleEvent(event)
            self.recordPendingExitPlanModeFollowUpEventIfNeeded(subscriptionToken: token)
            return true
        }
    }

    nonisolated func flushSubscriptionChunkBuffer(
        _ chunkBuffer: inout SubscriptionChunkBuffer,
        token: UUID
    ) async -> Bool {
        guard let pending = chunkBuffer.takePending() else {
            return true
        }

        return await MainActor.run { [weak self] in
            guard let self,
                  self.state.activeSubscriptionToken == token else {
                return false
            }

            self.state.lastObservedEventIndex += pending.eventCount
            self.handleEvent(.messageChunk(text: pending.text, parentToolUseId: nil))
            self.recordPendingExitPlanModeFollowUpEventIfNeeded(subscriptionToken: token)
            return true
        }
    }

    nonisolated func handleBufferedSubscriptionEvent(_ event: ConversationEvent, token: UUID) async -> Bool {
        await MainActor.run { [weak self] in
            guard let self,
                  self.state.activeSubscriptionToken == token else {
                return false
            }

            self.state.lastObservedEventIndex += 1
            self.handleEvent(event)
            self.recordPendingExitPlanModeFollowUpEventIfNeeded(subscriptionToken: token)
            return true
        }
    }

    nonisolated func finishSubscription(token: UUID) async {
        await MainActor.run { [weak self] in
            guard let self,
                  !Task.isCancelled,
                  self.state.activeSubscriptionToken == token else {
                return
            }

            let wasActive = self.state.turnState.isActive
            self.state.turnState.endTurn()
            if wasActive {
                self.recordLocalVisibleTurnEndedIfNeeded()
            }
            self.state.clearStreamingText()
            if self.drainPendingExitPlanModeFollowUpAfterSubscriptionFinish(token: token) {
                self.handleTurnCompleted()
            }
        }
    }

    nonisolated func processSubscriptionEvent(
        _ event: ConversationEvent,
        chunkBuffer: inout SubscriptionChunkBuffer,
        token: UUID
    ) async -> Bool {
        if case .messageChunk(let text, let parentToolUseId) = event, parentToolUseId == nil {
            return await processRootMessageChunk(
                event,
                text: text,
                chunkBuffer: &chunkBuffer,
                token: token
            )
        }

        guard await flushSubscriptionChunkBuffer(&chunkBuffer, token: token) else {
            return false
        }
        guard await handleBufferedSubscriptionEvent(event, token: token) else {
            return false
        }
        if event.resetsPublishedRootChunk {
            chunkBuffer.resetPublishedState()
        }
        return true
    }

    nonisolated func processRootMessageChunk(
        _ event: ConversationEvent,
        text: String,
        chunkBuffer: inout SubscriptionChunkBuffer,
        token: UUID
    ) async -> Bool {
        if !chunkBuffer.hasPublishedRootChunk {
            guard await handleImmediateSubscriptionEvent(event, token: token) else {
                return false
            }
            chunkBuffer.markImmediatePublish()
            return true
        }

        chunkBuffer.append(text)
        guard chunkBuffer.shouldFlush else {
            return true
        }

        return await flushSubscriptionChunkBuffer(&chunkBuffer, token: token)
    }
}

private extension ConversationEvent {
    var resetsPublishedRootChunk: Bool {
        switch self {
        case .message(let role, _, let parentToolUseId):
            return role == "assistant" && parentToolUseId == nil
        case .tokens,
             .stop,
             .error,
             .runtimeActivity,
             .contextCompactionStarted,
             .contextCompactionCompleted,
             .contextCompactionFailed:
            return true
        default:
            return false
        }
    }
}

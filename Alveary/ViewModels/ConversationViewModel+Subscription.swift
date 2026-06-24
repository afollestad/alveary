import Foundation

private let streamingChunkBatchEventThreshold = 8
private let streamingChunkBatchCharacterThreshold = 160
private let streamingChunkMaxDelayNanos: UInt64 = 100_000_000

private enum SubscriptionLoopInput: Sendable {
    case event(ConversationEvent)
    case flushDeadline
    case finished
}

private enum SubscriptionTextStreamKind: Sendable, Equatable {
    case message
    case thought

    func event(text: String) -> ConversationEvent {
        switch self {
        case .message:
            return .messageChunk(text: text, parentToolUseId: nil)
        case .thought:
            return .thinking(content: text, parentToolUseId: nil)
        }
    }
}

// `runSubscription` owns this reader and creates at most one pending `next()` task at a time.
private final class SubscriptionEventReader: @unchecked Sendable {
    private var iterator: AsyncStream<ConversationEvent>.Iterator

    init(stream: AsyncStream<ConversationEvent>) {
        iterator = stream.makeAsyncIterator()
    }

    func next() async -> ConversationEvent? {
        await iterator.next()
    }
}

private struct SubscriptionChunkBuffer {
    var kind: SubscriptionTextStreamKind?
    var text = ""
    var eventCount = 0
    var hasPublishedRootChunk = false

    var hasPendingText: Bool {
        !text.isEmpty
    }

    var shouldFlush: Bool {
        eventCount >= streamingChunkBatchEventThreshold || text.count >= streamingChunkBatchCharacterThreshold
    }

    mutating func prepareFor(kind: SubscriptionTextStreamKind) {
        guard self.kind != kind else {
            return
        }
        self.kind = kind
        text = ""
        eventCount = 0
        hasPublishedRootChunk = false
    }

    mutating func append(_ chunk: String, kind: SubscriptionTextStreamKind) {
        prepareFor(kind: kind)
        text.append(chunk)
        eventCount += 1
    }

    mutating func markImmediatePublish() {
        hasPublishedRootChunk = true
    }

    mutating func resetPublishedState() {
        kind = nil
        hasPublishedRootChunk = false
    }

    mutating func takePending() -> PendingSubscriptionText? {
        guard let kind, !text.isEmpty else {
            return nil
        }

        let pending = PendingSubscriptionText(kind: kind, text: text, eventCount: eventCount)
        text = ""
        eventCount = 0
        hasPublishedRootChunk = true
        return pending
    }
}

private struct PendingSubscriptionText {
    let kind: SubscriptionTextStreamKind
    let text: String
    let eventCount: Int
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

        let reader = SubscriptionEventReader(stream: subscription.stream)
        var pendingEventTask: Task<ConversationEvent?, Never>?
        defer {
            pendingEventTask?.cancel()
        }

        var chunkBuffer = SubscriptionChunkBuffer()

        while !Task.isCancelled {
            if pendingEventTask == nil {
                pendingEventTask = Task {
                    await reader.next()
                }
            }
            guard let eventTask = pendingEventTask else {
                return
            }

            let input = await nextSubscriptionInput(
                pendingEventTask: eventTask,
                flushAfterDelay: chunkBuffer.hasPendingText
            )
            guard !Task.isCancelled else {
                return
            }
            if case .event = input {
                pendingEventTask = nil
            } else if case .finished = input {
                pendingEventTask = nil
            }
            guard await processSubscriptionInput(
                input,
                chunkBuffer: &chunkBuffer,
                token: token
            ) else {
                return
            }
        }
    }

    nonisolated func nextSubscriptionInput(
        pendingEventTask: Task<ConversationEvent?, Never>,
        flushAfterDelay: Bool
    ) async -> SubscriptionLoopInput {
        let race = AsyncStream<SubscriptionLoopInput>.makeStream()
        let eventSignalTask = Task {
            if let event = await pendingEventTask.value {
                race.continuation.yield(.event(event))
            } else {
                race.continuation.yield(.finished)
            }
        }
        let deadlineSignalTask: Task<Void, Never>?
        if flushAfterDelay {
            deadlineSignalTask = Task {
                do {
                    try await Task.sleep(nanoseconds: streamingChunkMaxDelayNanos)
                    race.continuation.yield(.flushDeadline)
                } catch {
                    race.continuation.finish()
                }
            }
        } else {
            deadlineSignalTask = nil
        }

        return await withTaskCancellationHandler {
            var iterator = race.stream.makeAsyncIterator()
            let input = await iterator.next() ?? .finished
            race.continuation.finish()
            eventSignalTask.cancel()
            deadlineSignalTask?.cancel()
            return input
        } onCancel: {
            pendingEventTask.cancel()
            eventSignalTask.cancel()
            deadlineSignalTask?.cancel()
            race.continuation.finish()
        }
    }

    nonisolated func processSubscriptionInput(
        _ input: SubscriptionLoopInput,
        chunkBuffer: inout SubscriptionChunkBuffer,
        token: UUID
    ) async -> Bool {
        switch input {
        case .event(let event):
            return await processSubscriptionEvent(event, chunkBuffer: &chunkBuffer, token: token)
        case .flushDeadline:
            return await flushSubscriptionChunkBuffer(&chunkBuffer, token: token)
        case .finished:
            guard await flushSubscriptionChunkBuffer(&chunkBuffer, token: token) else {
                return false
            }
            await finishSubscription(token: token)
            return false
        }
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
            self.handleEvent(pending.kind.event(text: pending.text))
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
            self.state.endTurn()
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
        if let rootText = event.rootTextStream {
            if chunkBuffer.kind != rootText.kind {
                guard await flushSubscriptionChunkBuffer(&chunkBuffer, token: token) else {
                    return false
                }
            }
            return await processRootTextChunk(
                event,
                kind: rootText.kind,
                text: rootText.text,
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

    nonisolated func processRootTextChunk(
        _ event: ConversationEvent,
        kind: SubscriptionTextStreamKind,
        text: String,
        chunkBuffer: inout SubscriptionChunkBuffer,
        token: UUID
    ) async -> Bool {
        chunkBuffer.prepareFor(kind: kind)
        if !chunkBuffer.hasPublishedRootChunk {
            guard await handleImmediateSubscriptionEvent(event, token: token) else {
                return false
            }
            chunkBuffer.markImmediatePublish()
            return true
        }

        chunkBuffer.append(text, kind: kind)
        guard chunkBuffer.shouldFlush else {
            return true
        }

        return await flushSubscriptionChunkBuffer(&chunkBuffer, token: token)
    }
}

private extension ConversationEvent {
    var rootTextStream: (kind: SubscriptionTextStreamKind, text: String)? {
        switch self {
        case .messageChunk(let text, let parentToolUseId) where parentToolUseId == nil:
            return (.message, text)
        case .thinking(let content, let parentToolUseId) where parentToolUseId == nil:
            return (.thought, content)
        default:
            return nil
        }
    }

    var resetsPublishedRootChunk: Bool {
        switch self {
        case .message(_, _, let parentToolUseId):
            return parentToolUseId == nil
        case .toolCall,
             .toolResult,
             .toolApprovalRequested,
             .toolApprovalFailed,
             .taskListSnapshot,
             .subAgentStarted,
             .subAgentProgress,
             .subAgentCompleted,
             .goal,
             .stop,
             .error,
             .runtimeActivity,
             .contextCompactionStarted,
             .contextCompactionCompleted,
             .contextCompactionFailed:
            return true
        case .tokens,
             .runtimeUserMessage,
             .steeredConversation:
            return true
        default:
            return false
        }
    }
}

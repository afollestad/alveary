import Foundation

/// Runtime state for a conversation's event stream. Keep this as a reference so
/// updating live-approval counters does not perform nested dictionary writes.
final class ManagedEventBuffer: @unchecked Sendable {
    let generation: UUID
    var allowsReplay: Bool
    var acceptsLiveEvents: Bool
    var hasDeferredToolStop: Bool
    var observedEventCount = 0
    var pendingLiveToolApprovals: Int
    var hasSentPendingUserActionNotification: Bool
    var hasSentProviderErrorNotification = false
    var resolvedLiveToolApprovals: Set<ClaudeToolApprovalKey>
    var deferredToolStopSessionId: String?
    var deferredToolStopToolUseId: String?
    var currentTurnActivityVisibility: AgentTurnActivityVisibility = .hidden
    var hasRecordedTerminalThreadActivity = false
    var lastKnownRuntimeTurnActive = false
    var latestTerminalRuntimeEventIndex: Int?
    private var agentCLIKitEnvelopeIndexByObservedIndex: [Int: Int] = [:]
    let buffer: EventBuffer

    init(
        generation: UUID,
        allowsReplay: Bool,
        acceptsLiveEvents: Bool,
        hasDeferredToolStop: Bool,
        pendingLiveToolApprovals: Int,
        hasSentPendingUserActionNotification: Bool,
        resolvedLiveToolApprovals: Set<ClaudeToolApprovalKey>,
        deferredToolStopSessionId: String?,
        deferredToolStopToolUseId: String?,
        buffer: EventBuffer
    ) {
        self.generation = generation
        self.allowsReplay = allowsReplay
        self.acceptsLiveEvents = acceptsLiveEvents
        self.hasDeferredToolStop = hasDeferredToolStop
        self.pendingLiveToolApprovals = pendingLiveToolApprovals
        self.hasSentPendingUserActionNotification = hasSentPendingUserActionNotification
        self.resolvedLiveToolApprovals = resolvedLiveToolApprovals
        self.deferredToolStopSessionId = deferredToolStopSessionId
        self.deferredToolStopToolUseId = deferredToolStopToolUseId
        self.buffer = buffer
    }

    func recordAgentCLIKitEnvelopeIndex(_ envelopeIndex: Int) {
        guard observedEventCount > 0 else {
            return
        }
        agentCLIKitEnvelopeIndexByObservedIndex[observedEventCount] = envelopeIndex
    }

    func agentCLIKitEnvelopeIndex(upToObservedIndex observedIndex: Int) -> Int? {
        guard let key = agentCLIKitEnvelopeIndexByObservedIndex.keys.filter({ $0 <= observedIndex }).max(),
              let envelopeIndex = agentCLIKitEnvelopeIndexByObservedIndex[key] else {
            return nil
        }
        agentCLIKitEnvelopeIndexByObservedIndex = agentCLIKitEnvelopeIndexByObservedIndex.filter { $0.key >= key }
        return envelopeIndex
    }
}

final class EventBuffer: @unchecked Sendable {
    /// Target replay-window size after a batch compaction. Because persisted prefixes are
    /// evicted in batches, `retainedCount` may sit slightly above this between evictions.
    private static let maxRetained = 5000
    private static let evictionBatch = 256

    private let lock = NSLock()
    private var events: [ConversationEvent] = []
    private var continuations: [UUID: AsyncStream<ConversationEvent>.Continuation] = [:]
    private var persistedIndex = 0
    private var isFinished = false
    private var baseOffset = 0

    func push(_ event: ConversationEvent) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }

        events.append(event)

        if events.count > Self.maxRetained + Self.evictionBatch,
           persistedIndex > baseOffset {
            let localPersisted = persistedIndex - baseOffset
            let overflow = events.count - Self.maxRetained
            let evictCount = min(localPersisted, max(Self.evictionBatch, overflow))
            if evictCount > 0 {
                events.removeFirst(evictCount)
                baseOffset += evictCount
            }
        }

        let activeContinuations = Array(continuations)
        for (_, continuation) in activeContinuations {
            continuation.yield(event)
        }
        lock.unlock()
    }

    func markPersisted(upTo index: Int) {
        lock.lock()
        persistedIndex = max(persistedIndex, index)
        lock.unlock()
    }

    func subscribe(afterIndex: Int = 0) -> (stream: AsyncStream<ConversationEvent>, id: UUID) {
        let subscriptionID = UUID()

        lock.lock()
        let localIndex = min(max(afterIndex - baseOffset, 0), events.count)
        let snapshot = localIndex < events.count ? Array(events[localIndex...]) : []
        let snapshotGlobalEnd = baseOffset + events.count
        lock.unlock()

        let stream = AsyncStream<ConversationEvent> { continuation in
            for event in snapshot {
                continuation.yield(event)
            }

            var shouldFinishImmediately = false
            self.lock.lock()
            let localStart = min(max(snapshotGlobalEnd - self.baseOffset, 0), self.events.count)
            let missed = localStart < self.events.count ? Array(self.events[localStart...]) : []
            for event in missed {
                continuation.yield(event)
            }
            if self.isFinished {
                shouldFinishImmediately = true
            } else {
                self.continuations[subscriptionID] = continuation
            }
            self.lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.unsubscribe(subscriptionID)
            }

            if shouldFinishImmediately {
                continuation.finish()
            }
        }

        return (stream, subscriptionID)
    }

    func unsubscribe(_ id: UUID) {
        lock.lock()
        continuations.removeValue(forKey: id)
        lock.unlock()
    }

    /// Number of events currently retained in memory after any persisted-prefix eviction.
    /// This is the live in-memory window, not the global event count, and batched eviction
    /// means it may temporarily exceed `maxRetained` by less than one batch.
    var retainedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return events.count
    }

    var hasSubscribers: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !continuations.isEmpty
    }

    var hasUnpersistedEvents: Bool {
        lock.lock()
        defer { lock.unlock() }
        return (baseOffset + events.count) > persistedIndex
    }

    func finishAll() {
        lock.lock()
        isFinished = true
        let toFinish = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()

        for continuation in toFinish {
            continuation.finish()
        }
    }
}

final class PendingStdinWrite {
    let id: UUID
    var task: Task<Void, Error>?

    init(id: UUID) {
        self.id = id
    }

    func cancel() {
        task?.cancel()
    }
}

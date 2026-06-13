import Foundation
import SwiftData

@MainActor
protocol ThreadActivityRecording: AnyObject, Sendable {
    func recordVisibleOutbound(conversationId: String)
    func recordVisibleTurnEnded(conversationId: String)
    func recordHistoricalActivity(conversationId: String, timestamp: Date)
    func backfillMissingModifiedDates(batchSize: Int) async
}

@MainActor
final class ThreadActivityRecorder: ThreadActivityRecording {
    typealias DateProvider = @MainActor @Sendable () -> Date

    private let modelContext: ModelContext
    private let dateProvider: DateProvider

    init(
        modelContext: ModelContext,
        dateProvider: @escaping DateProvider = { Date.now }
    ) {
        self.modelContext = modelContext
        self.dateProvider = dateProvider
    }

    func recordVisibleOutbound(conversationId: String) {
        recordLiveActivity(conversationId: conversationId)
    }

    func recordVisibleTurnEnded(conversationId: String) {
        recordLiveActivity(conversationId: conversationId)
    }

    func recordHistoricalActivity(conversationId: String, timestamp: Date) {
        recordActivity(
            conversationId: conversationId,
            timestamp: timestamp,
            forcesMonotonicTimestamp: false,
            postsNotification: true
        )
    }

    func backfillMissingModifiedDates(batchSize: Int = 100) async {
        let threadIDs = missingModifiedThreadIDs()
        guard !threadIDs.isEmpty else {
            return
        }

        var processed = 0
        let resolvedBatchSize = max(batchSize, 1)
        var didChangeAnyOrder = false
        for threadID in threadIDs {
            processed += 1
            let shouldYield = processed % resolvedBatchSize == 0
            guard let thread = modelContext.resolveThread(id: threadID),
                  thread.modifiedAt == nil,
                  let timestamp = latestHistoricalActivityTimestamp(for: thread) else {
                if shouldYield {
                    await Task.yield()
                }
                continue
            }
            let didChangeOrder = applyActivity(
                to: thread,
                conversationId: nil,
                timestamp: timestamp,
                forcesMonotonicTimestamp: false,
                postsNotification: false
            )
            didChangeAnyOrder = didChangeAnyOrder || didChangeOrder
            if shouldYield {
                await Task.yield()
            }
        }

        guard didChangeAnyOrder else {
            return
        }
        NotificationCenter.default.post(
            name: .threadActivityChanged,
            object: nil,
            userInfo: [
                ThreadActivityNotificationKey.didChangeOrder: true,
                ThreadActivityNotificationKey.isBackfill: true
            ]
        )
    }

    private func recordLiveActivity(conversationId: String) {
        recordActivity(
            conversationId: conversationId,
            timestamp: dateProvider(),
            forcesMonotonicTimestamp: true,
            postsNotification: true
        )
    }

    private func recordActivity(
        conversationId: String,
        timestamp: Date,
        forcesMonotonicTimestamp: Bool,
        postsNotification: Bool
    ) {
        guard let thread = modelContext.resolveThread(conversationID: conversationId) else {
            return
        }
        _ = applyActivity(
            to: thread,
            conversationId: conversationId,
            timestamp: timestamp,
            forcesMonotonicTimestamp: forcesMonotonicTimestamp,
            postsNotification: postsNotification
        )
    }

    @discardableResult
    private func applyActivity(
        to thread: AgentThread,
        conversationId: String?,
        timestamp: Date,
        forcesMonotonicTimestamp: Bool,
        postsNotification: Bool
    ) -> Bool {
        guard thread.archivedAt == nil,
              let projectPath = thread.project?.path else {
            return false
        }

        let currentTimestamp = thread.modifiedAt
        let resolvedTimestamp: Date
        if let currentTimestamp, timestamp <= currentTimestamp {
            guard forcesMonotonicTimestamp else {
                return false
            }
            resolvedTimestamp = currentTimestamp.addingTimeInterval(0.000_001)
        } else {
            resolvedTimestamp = timestamp
        }

        let beforeOrder = orderedThreadIDs(projectPath: projectPath)
        thread.modifiedAt = resolvedTimestamp
        do {
            try modelContext.save()
        } catch {
            thread.modifiedAt = currentTimestamp
            return false
        }
        let afterOrder = orderedThreadIDs(projectPath: projectPath)
        let didChangeOrder = beforeOrder != afterOrder

        if postsNotification {
            postActivityChanged(
                projectPath: projectPath,
                threadID: thread.persistentModelID,
                conversationId: conversationId,
                didChangeOrder: didChangeOrder
            )
        }
        return didChangeOrder
    }

    private func postActivityChanged(
        projectPath: String,
        threadID: PersistentIdentifier,
        conversationId: String?,
        didChangeOrder: Bool
    ) {
        var userInfo: [String: Any] = [
            ThreadActivityNotificationKey.projectPath: projectPath,
            ThreadActivityNotificationKey.threadID: threadID,
            ThreadActivityNotificationKey.didChangeOrder: didChangeOrder
        ]
        if let conversationId {
            userInfo[ThreadActivityNotificationKey.conversationID] = conversationId
        }
        NotificationCenter.default.post(name: .threadActivityChanged, object: nil, userInfo: userInfo)
    }

    private func orderedThreadIDs(projectPath: String) -> [PersistentIdentifier] {
        AgentThreadOrdering.orderedIDs(activeThreads(projectPath: projectPath))
    }

    private func activeThreads(projectPath: String) -> [AgentThread] {
        let descriptor = FetchDescriptor<AgentThread>(
            predicate: #Predicate { thread in
                thread.archivedAt == nil && thread.project?.path == projectPath
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func missingModifiedThreadIDs() -> [PersistentIdentifier] {
        var descriptor = FetchDescriptor<AgentThread>(
            predicate: #Predicate { thread in
                thread.modifiedAt == nil && thread.archivedAt == nil
            }
        )
        descriptor.sortBy = [SortDescriptor(\.name)]
        let threads = (try? modelContext.fetch(descriptor)) ?? []
        return threads.map(\.persistentModelID)
    }

    private func latestHistoricalActivityTimestamp(for thread: AgentThread) -> Date? {
        let conversationIDs = thread.conversations.map(\.id)
        return conversationIDs.compactMap(latestHistoricalActivityTimestamp).max()
    }

    private func latestHistoricalActivityTimestamp(conversationId: String) -> Date? {
        let descriptor = FetchDescriptor<ConversationEventRecord>(
            predicate: #Predicate { record in
                record.conversationId == conversationId
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let records = (try? modelContext.fetch(descriptor)) ?? []
        return records.first(where: isHistoricalActivityRecord)?.timestamp
    }

    private func isHistoricalActivityRecord(_ record: ConversationEventRecord) -> Bool {
        switch record.type {
        case "message":
            return record.role == "user"
        case "stop":
            return true
        case "error":
            return record.toolId == nil && record.toolName == nil
        case "tokens":
            if record.isError {
                return true
            }
            guard let stopReason = record.stopReason else {
                return false
            }
            return stopReason != ConversationEvent.interimUsageStopReason &&
                stopReason != "tool_use"
        default:
            return false
        }
    }
}

enum ThreadActivityNotificationKey {
    static let projectPath = "projectPath"
    static let threadID = "threadID"
    static let conversationID = "conversationID"
    static let didChangeOrder = "didChangeOrder"
    static let isBackfill = "isBackfill"
}

extension Notification.Name {
    static let threadActivityChanged = Notification.Name("threadActivityChanged")
}

@MainActor
final class NoopThreadActivityRecorder: ThreadActivityRecording {
    func recordVisibleOutbound(conversationId: String) {}
    func recordVisibleTurnEnded(conversationId: String) {}
    func recordHistoricalActivity(conversationId: String, timestamp: Date) {}
    func backfillMissingModifiedDates(batchSize: Int = 100) async {}
}

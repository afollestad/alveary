import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ThreadActivityRecorderTests: XCTestCase {
    func testDraftThreadIgnoresVisibleActivity() throws {
        let fixture = try ThreadActivityRecorderFixture()
        let draft = fixture.insertThread(
            name: "Draft",
            modifiedAt: nil,
            conversationIDs: ["draft-main"],
            isDraft: true
        )
        try fixture.save()

        fixture.recorder.recordVisibleOutbound(conversationId: "draft-main")

        XCTAssertNil(draft.modifiedAt)
    }

    func testVisibleOutboundUpdatesThreadAndPostsPayload() async throws {
        let clock = ManualDateProvider(now: Date(timeIntervalSince1970: 300))
        let fixture = try ThreadActivityRecorderFixture(clock: clock)
        let older = fixture.insertThread(name: "Older", modifiedAt: Date(timeIntervalSince1970: 100), conversationIDs: ["older-main"])
        _ = fixture.insertThread(name: "Newer", modifiedAt: Date(timeIntervalSince1970: 200), conversationIDs: ["newer-main"])
        try fixture.save()

        let expectation = expectation(description: "thread activity notification")
        let notificationPayload = NotificationPayloadRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: .threadActivityChanged,
            object: nil,
            queue: nil
        ) { notification in
            guard notification.userInfo?[ThreadActivityNotificationKey.conversationID] as? String == "older-main" else {
                return
            }
            notificationPayload.record(notification.userInfo)
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        fixture.recorder.recordVisibleOutbound(conversationId: "older-main")

        await fulfillment(of: [expectation], timeout: 1)
        let payload = notificationPayload.payload()
        XCTAssertEqual(older.modifiedAt, clock.now)
        XCTAssertEqual(payload?[ThreadActivityNotificationKey.projectPath] as? String, fixture.project.path)
        XCTAssertEqual(payload?[ThreadActivityNotificationKey.threadID] as? PersistentIdentifier, older.persistentModelID)
        XCTAssertEqual(payload?[ThreadActivityNotificationKey.conversationID] as? String, "older-main")
        XCTAssertEqual(payload?[ThreadActivityNotificationKey.didChangeOrder] as? Bool, true)
    }

    func testVisibleTurnEndUsesStrictlyMonotonicTimestampWithoutOrderChange() async throws {
        let baseDate = Date(timeIntervalSince1970: 300)
        let clock = ManualDateProvider(now: baseDate)
        let fixture = try ThreadActivityRecorderFixture(clock: clock)
        let currentTop = fixture.insertThread(name: "Current", modifiedAt: baseDate, conversationIDs: ["current-main"])
        _ = fixture.insertThread(name: "Older", modifiedAt: Date(timeIntervalSince1970: 200), conversationIDs: ["older-main"])
        try fixture.save()

        let expectation = expectation(description: "thread activity notification")
        let notificationPayload = NotificationPayloadRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: .threadActivityChanged,
            object: nil,
            queue: nil
        ) { notification in
            guard notification.userInfo?[ThreadActivityNotificationKey.conversationID] as? String == "current-main" else {
                return
            }
            notificationPayload.record(notification.userInfo)
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        fixture.recorder.recordVisibleTurnEnded(conversationId: "current-main")

        await fulfillment(of: [expectation], timeout: 1)
        let modifiedAt = try XCTUnwrap(currentTop.modifiedAt)
        XCTAssertGreaterThan(modifiedAt, baseDate)
        XCTAssertEqual(notificationPayload.payload()?[ThreadActivityNotificationKey.didChangeOrder] as? Bool, false)
    }

    func testPinnedVisibleTurnEndDoesNotPostOrderChange() async throws {
        let baseDate = Date(timeIntervalSince1970: 300)
        let clock = ManualDateProvider(now: baseDate)
        let fixture = try ThreadActivityRecorderFixture(clock: clock)
        let pinned = fixture.insertThread(
            name: "Pinned",
            modifiedAt: baseDate,
            conversationIDs: ["pinned-main"],
            isPinned: true
        )
        _ = fixture.insertThread(name: "Unpinned", modifiedAt: Date(timeIntervalSince1970: 200), conversationIDs: ["unpinned-main"])
        try fixture.save()

        let expectation = expectation(description: "thread activity notification")
        let notificationPayload = NotificationPayloadRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: .threadActivityChanged,
            object: nil,
            queue: nil
        ) { notification in
            guard notification.userInfo?[ThreadActivityNotificationKey.conversationID] as? String == "pinned-main" else {
                return
            }
            notificationPayload.record(notification.userInfo)
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        fixture.recorder.recordVisibleTurnEnded(conversationId: "pinned-main")

        await fulfillment(of: [expectation], timeout: 1)
        let modifiedAt = try XCTUnwrap(pinned.modifiedAt)
        XCTAssertGreaterThan(modifiedAt, baseDate)
        XCTAssertEqual(notificationPayload.payload()?[ThreadActivityNotificationKey.didChangeOrder] as? Bool, false)
    }

    func testTaskVisibleOutboundUsesGlobalTaskOrderingAndOmitsProjectPath() async throws {
        let clock = ManualDateProvider(now: Date(timeIntervalSince1970: 300))
        let fixture = try ThreadActivityRecorderFixture(clock: clock)
        let older = fixture.insertThread(
            name: "Older task",
            modifiedAt: Date(timeIntervalSince1970: 100),
            conversationIDs: ["older-task"],
            mode: .task
        )
        _ = fixture.insertThread(
            name: "Newer task",
            modifiedAt: Date(timeIntervalSince1970: 200),
            conversationIDs: ["newer-task"],
            mode: .task
        )
        try fixture.save()
        let expectation = expectation(description: "task activity notification")
        let notificationPayload = NotificationPayloadRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: .threadActivityChanged,
            object: nil,
            queue: nil
        ) { notification in
            guard notification.userInfo?[ThreadActivityNotificationKey.conversationID] as? String == "older-task" else {
                return
            }
            notificationPayload.record(notification.userInfo)
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        fixture.recorder.recordVisibleOutbound(conversationId: "older-task")

        await fulfillment(of: [expectation], timeout: 1)
        let payload = notificationPayload.payload()
        XCTAssertEqual(older.modifiedAt, clock.now)
        XCTAssertEqual(payload?[ThreadActivityNotificationKey.threadMode] as? String, AgentThreadMode.task.rawValue)
        XCTAssertNil(payload?[ThreadActivityNotificationKey.projectPath])
        XCTAssertEqual(payload?[ThreadActivityNotificationKey.didChangeOrder] as? Bool, true)
    }

    func testLinkedScheduledRunUsesTaskActivityScopeWhenPersistedModeFallsBackToProject() async throws {
        let clock = ManualDateProvider(now: Date(timeIntervalSince1970: 300))
        let fixture = try ThreadActivityRecorderFixture(clock: clock)
        let linkedTask = fixture.insertThread(
            name: "Fallback scheduled task",
            modifiedAt: Date(timeIntervalSince1970: 100),
            conversationIDs: ["fallback-scheduled-task"]
        )
        linkedTask.modeRawValue = "future-mode"
        let run = makeThreadActivityScheduledRun()
        run.thread = linkedTask
        linkedTask.scheduledTaskRun = run
        fixture.context.insert(run)
        try fixture.save()
        let expectation = expectation(description: "fallback scheduled task activity notification")
        let notificationPayload = NotificationPayloadRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: .threadActivityChanged,
            object: nil,
            queue: nil
        ) { notification in
            guard notification.userInfo?[ThreadActivityNotificationKey.conversationID] as? String == "fallback-scheduled-task" else {
                return
            }
            notificationPayload.record(notification.userInfo)
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        fixture.recorder.recordVisibleOutbound(conversationId: "fallback-scheduled-task")

        await fulfillment(of: [expectation], timeout: 1)
        let payload = notificationPayload.payload()
        XCTAssertEqual(linkedTask.modifiedAt, clock.now)
        XCTAssertEqual(payload?[ThreadActivityNotificationKey.threadMode] as? String, AgentThreadMode.task.rawValue)
        XCTAssertNil(payload?[ThreadActivityNotificationKey.projectPath])
    }

    func testPinnedTaskActivityUpdatesTimestampWithoutChangingTaskOrder() async throws {
        let clock = ManualDateProvider(now: Date(timeIntervalSince1970: 300))
        let fixture = try ThreadActivityRecorderFixture(clock: clock)
        let pinned = fixture.insertThread(
            name: "Pinned task",
            modifiedAt: Date(timeIntervalSince1970: 100),
            conversationIDs: ["pinned-task"],
            isPinned: true,
            mode: .task
        )
        _ = fixture.insertThread(
            name: "Unpinned task",
            modifiedAt: Date(timeIntervalSince1970: 200),
            conversationIDs: ["unpinned-task"],
            mode: .task
        )
        try fixture.save()
        let expectation = expectation(description: "pinned task activity notification")
        let notificationPayload = NotificationPayloadRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: .threadActivityChanged,
            object: nil,
            queue: nil
        ) { notification in
            guard notification.userInfo?[ThreadActivityNotificationKey.conversationID] as? String == "pinned-task" else {
                return
            }
            notificationPayload.record(notification.userInfo)
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        fixture.recorder.recordVisibleTurnEnded(conversationId: "pinned-task")

        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(pinned.modifiedAt, clock.now)
        XCTAssertEqual(notificationPayload.payload()?[ThreadActivityNotificationKey.didChangeOrder] as? Bool, false)
    }

    func testPinnedProjectChildVisibleTurnEndPostsOrderChange() async throws {
        let currentDate = Date(timeIntervalSince1970: 100)
        let clock = ManualDateProvider(now: Date(timeIntervalSince1970: 300))
        let fixture = try ThreadActivityRecorderFixture(clock: clock)
        fixture.project.isPinned = true
        let child = fixture.insertThread(
            name: "Child",
            modifiedAt: currentDate,
            conversationIDs: ["child-main"]
        )
        _ = fixture.insertThread(name: "Sibling", modifiedAt: Date(timeIntervalSince1970: 200), conversationIDs: ["sibling-main"])
        try fixture.save()

        let expectation = expectation(description: "pinned project child activity notification")
        let notificationPayload = NotificationPayloadRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: .threadActivityChanged,
            object: nil,
            queue: nil
        ) { notification in
            guard notification.userInfo?[ThreadActivityNotificationKey.conversationID] as? String == "child-main" else {
                return
            }
            notificationPayload.record(notification.userInfo)
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        fixture.recorder.recordVisibleTurnEnded(conversationId: "child-main")

        await fulfillment(of: [expectation], timeout: 1)
        let modifiedAt = try XCTUnwrap(child.modifiedAt)
        XCTAssertGreaterThan(modifiedAt, currentDate)
        XCTAssertEqual(notificationPayload.payload()?[ThreadActivityNotificationKey.didChangeOrder] as? Bool, true)
    }

    func testHistoricalActivityIgnoresStaleTimestamp() throws {
        let fixture = try ThreadActivityRecorderFixture()
        let current = Date(timeIntervalSince1970: 300)
        let thread = fixture.insertThread(name: "Current", modifiedAt: current, conversationIDs: ["current-main"])
        try fixture.save()

        fixture.recorder.recordHistoricalActivity(
            conversationId: "current-main",
            timestamp: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(thread.modifiedAt, current)
    }

    func testBackfillUsesLatestQualifyingHistoricalEventAcrossConversations() async throws {
        let fixture = try ThreadActivityRecorderFixture()
        let thread = fixture.insertThread(name: "Thread", modifiedAt: nil, conversationIDs: ["main", "side"])
        let main = try XCTUnwrap(thread.conversations.first { $0.id == "main" })
        let side = try XCTUnwrap(thread.conversations.first { $0.id == "side" })
        let expected = Date(timeIntervalSince1970: 400)
        fixture.insertEvent(conversation: main, type: "message", role: "user", timestamp: Date(timeIntervalSince1970: 100))
        fixture.insertEvent(conversation: main, type: "error", toolId: "tool-1", toolName: "Read", timestamp: Date(timeIntervalSince1970: 500))
        fixture.insertEvent(conversation: side, type: "tokens", stopReason: "usage_update", timestamp: Date(timeIntervalSince1970: 450))
        fixture.insertEvent(conversation: side, type: "tokens", stopReason: "tool_deferred", timestamp: expected)
        try fixture.save()

        await fixture.recorder.backfillMissingModifiedDates(batchSize: 1)

        XCTAssertEqual(thread.modifiedAt, expected)
    }

    func testBackfillDoesNotOverwriteLiveActivity() async throws {
        let clock = ManualDateProvider(now: Date(timeIntervalSince1970: 500))
        let fixture = try ThreadActivityRecorderFixture(clock: clock)
        let thread = fixture.insertThread(name: "Thread", modifiedAt: nil, conversationIDs: ["main"])
        let conversation = try XCTUnwrap(thread.conversations.first)
        fixture.insertEvent(conversation: conversation, type: "stop", timestamp: Date(timeIntervalSince1970: 100))
        try fixture.save()

        fixture.recorder.recordVisibleOutbound(conversationId: "main")
        await fixture.recorder.backfillMissingModifiedDates(batchSize: 1)

        XCTAssertEqual(thread.modifiedAt, clock.now)
    }
}

@MainActor
private final class ManualDateProvider {
    var now: Date

    init(now: Date = Date(timeIntervalSince1970: 100)) {
        self.now = now
    }
}

@MainActor
private final class ThreadActivityRecorderFixture {
    let container: ModelContainer
    let context: ModelContext
    let project: Project
    let recorder: ThreadActivityRecorder

    init(clock: ManualDateProvider? = nil) throws {
        let clock = clock ?? ManualDateProvider()
        container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        project = Project(path: "/tmp/alveary-project", name: "Alveary")
        recorder = ThreadActivityRecorder(modelContext: context, dateProvider: { clock.now })
        context.insert(project)
    }

    func insertThread(
        name: String,
        modifiedAt: Date?,
        conversationIDs: [String],
        isPinned: Bool = false,
        isDraft: Bool = false,
        mode: AgentThreadMode = .project
    ) -> AgentThread {
        let taskWorkspace = mode == .task
            ? TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/task-\(conversationIDs.first ?? "workspace")",
                ownershipStrategy: .privateOwned
            )
            : nil
        let thread = AgentThread(
            name: name,
            isPinned: isPinned,
            isDraft: isDraft,
            modifiedAt: modifiedAt,
            mode: mode,
            taskWorkspaceDescriptor: taskWorkspace,
            project: mode == .project ? project : nil
        )
        thread.conversations = conversationIDs.enumerated().map { index, id in
            Conversation(
                id: id,
                title: id,
                isMain: index == 0,
                displayOrder: index,
                thread: thread
            )
        }
        if mode == .project {
            project.threads.append(thread)
        }
        context.insert(thread)
        thread.conversations.forEach(context.insert)
        return thread
    }

    func insertEvent(
        conversation: Conversation,
        type: String,
        role: String? = nil,
        toolId: String? = nil,
        toolName: String? = nil,
        stopReason: String? = nil,
        isError: Bool = false,
        timestamp: Date
    ) {
        let record = ConversationEventRecord(
            type: type,
            role: role,
            toolId: toolId,
            toolName: toolName,
            isError: isError,
            stopReason: stopReason,
            timestamp: timestamp,
            conversation: conversation
        )
        conversation.events.append(record)
        context.insert(record)
    }

    func save() throws {
        try context.save()
    }
}

private final class NotificationPayloadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedPayload: [AnyHashable: Any]?

    func record(_ payload: [AnyHashable: Any]?) {
        lock.withLock {
            recordedPayload = payload
        }
    }

    func payload() -> [AnyHashable: Any]? {
        lock.withLock {
            recordedPayload
        }
    }
}

private func makeThreadActivityScheduledRun() -> ScheduledTaskRun {
    ScheduledTaskRun(
        occurrenceID: UUID().uuidString,
        definitionID: "thread-activity-definition",
        definitionRevision: 1,
        occurrenceAt: Date(timeIntervalSinceReferenceDate: 1_000),
        triggerKind: .scheduled,
        status: .success,
        titleSnapshot: "Scheduled task",
        promptSnapshot: "Run scheduled work.",
        timeZoneIdentifierSnapshot: "UTC",
        providerIDSnapshot: "codex",
        effortSnapshot: "high",
        permissionModeSnapshot: "default",
        workspaceKindSnapshot: .privateWorkspace,
        workspaceStrategySnapshot: .worktree
    )
}

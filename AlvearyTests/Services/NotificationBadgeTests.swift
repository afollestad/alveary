import SwiftData
import XCTest

@testable import Alveary

private actor BadgeCallRecorder {
    private var values: [Int] = []

    func append(_ value: Int) {
        values.append(value)
    }

    func snapshot() -> [Int] {
        values
    }
}

@MainActor
final class NotificationBadgeTests: XCTestCase {
    func testMarkConversationReadClearsUnreadDismissesAndUpdatesBadge() async throws {
        let service = InMemorySettingsService()
        let spy = NotificationSpy()
        let context = try NotificationManagerTestFactory.makeContext()
        let conversation = NotificationManagerTestFactory.seedConversation(
            in: context.container,
            threadName: "Thread",
            isUnread: true
        )
        let manager = NotificationManagerTestFactory.makeManager(
            settingsService: service,
            modelContainer: context.container,
            isAppInForeground: true,
            activeConversationId: conversation.id,
            spy: spy
        )

        manager.markConversationRead(conversationId: conversation.id)
        await manager.awaitPendingBadgeUpdate()

        XCTAssertFalse(
            NotificationManagerTestFactory.fetchConversation(id: conversation.id, in: context.container)?.isUnread ?? true
        )
        XCTAssertEqual(spy.dismissedConversationIds, [conversation.id])
        XCTAssertEqual(spy.badgeCounts.last, 0)
    }

    func testRefreshBadgeCountReflectsUnreadCount() async throws {
        let service = InMemorySettingsService()
        let spy = NotificationSpy()
        let context = try NotificationManagerTestFactory.makeContext()
        _ = NotificationManagerTestFactory.seedConversation(in: context.container, threadName: "A", isUnread: true)
        _ = NotificationManagerTestFactory.seedConversation(in: context.container, threadName: "B", isUnread: true)
        _ = NotificationManagerTestFactory.seedConversation(in: context.container, threadName: "C", isUnread: false)
        let manager = NotificationManagerTestFactory.makeManager(
            settingsService: service,
            modelContainer: context.container,
            isAppInForeground: true,
            activeConversationId: nil,
            spy: spy
        )

        manager.refreshBadgeCount()
        await manager.awaitPendingBadgeUpdate()

        XCTAssertEqual(spy.badgeCounts.last, 2)
    }

    func testRapidRefreshBadgeCallsPreserveLastValue() async throws {
        let service = InMemorySettingsService()
        let spy = NotificationSpy()
        let context = try NotificationManagerTestFactory.makeContext()
        let first = NotificationManagerTestFactory.seedConversation(in: context.container, threadName: "A", isUnread: true)
        let second = NotificationManagerTestFactory.seedConversation(in: context.container, threadName: "B", isUnread: true)
        let manager = NotificationManagerTestFactory.makeManager(
            settingsService: service,
            modelContainer: context.container,
            isAppInForeground: true,
            activeConversationId: nil,
            spy: spy
        )

        manager.refreshBadgeCount()                               // count = 2
        manager.markConversationRead(conversationId: first.id)    // count = 1, calls refresh
        manager.markConversationRead(conversationId: second.id)   // count = 0, calls refresh
        await manager.awaitPendingBadgeUpdate()

        XCTAssertEqual(spy.badgeCounts, [2, 1, 0])
    }

    func testRefreshBadgeCountChainsSystemCallsInSubmissionOrder() async throws {
        let service = InMemorySettingsService()
        let context = try NotificationManagerTestFactory.makeContext()
        let first = NotificationManagerTestFactory.seedConversation(in: context.container, threadName: "A", isUnread: true)
        _ = NotificationManagerTestFactory.seedConversation(in: context.container, threadName: "B", isUnread: true)
        let manager = DefaultNotificationManager(
            settingsService: service,
            modelContainer: context.container,
            systemNotificationCenter: NotificationCenter()
        )

        let recorder = BadgeCallRecorder()
        manager.setBadgeCount = { count in
            // If chaining is broken, the second submitted task (count = 1) could finish and record
            // before the first (count = 2). Yielding on the first-submitted call amplifies any race.
            if count == 2 {
                for _ in 0..<10 {
                    await Task.yield()
                }
            }
            await recorder.append(count)
        }

        manager.refreshBadgeCount()                               // submits count = 2
        manager.markConversationRead(conversationId: first.id)    // submits count = 1
        await manager.awaitPendingBadgeUpdate()

        let recorded = await recorder.snapshot()
        XCTAssertEqual(recorded, [2, 1])
    }

    func testRefreshBadgeCountExcludesConversationsInArchivedThreads() async throws {
        let service = InMemorySettingsService()
        let spy = NotificationSpy()
        let context = try NotificationManagerTestFactory.makeContext()
        _ = NotificationManagerTestFactory.seedConversation(in: context.container, threadName: "Active", isUnread: true)
        _ = NotificationManagerTestFactory.seedConversation(
            in: context.container,
            threadName: "Archived",
            isUnread: true,
            archivedAt: Date()
        )
        let manager = NotificationManagerTestFactory.makeManager(
            settingsService: service,
            modelContainer: context.container,
            isAppInForeground: true,
            activeConversationId: nil,
            spy: spy
        )

        manager.refreshBadgeCount()
        await manager.awaitPendingBadgeUpdate()

        XCTAssertEqual(spy.badgeCounts.last, 1)
    }

    func testHandleEventMarkingUnreadPostsAgentStatusChanged() throws {
        let service = InMemorySettingsService()
        let spy = NotificationSpy()
        let context = try NotificationManagerTestFactory.makeContext()
        let conversation = NotificationManagerTestFactory.seedConversation(in: context.container, threadName: "Thread")
        let manager = NotificationManagerTestFactory.makeManager(
            settingsService: service,
            modelContainer: context.container,
            isAppInForeground: false,
            activeConversationId: nil,
            spy: spy
        )

        let expectation = expectation(description: "agent status notification")
        let observer = NotificationCenter.default.addObserver(
            forName: .agentStatusChanged,
            object: nil,
            queue: .main
        ) { notification in
            if notification.userInfo?["conversationId"] as? String == conversation.id {
                expectation.fulfill()
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        manager.handleEvent(.stop(message: nil), conversationId: conversation.id)

        wait(for: [expectation], timeout: 0.5)
    }

    func testMarkConversationReadPostsAgentStatusChanged() throws {
        let service = InMemorySettingsService()
        let spy = NotificationSpy()
        let context = try NotificationManagerTestFactory.makeContext()
        let conversation = NotificationManagerTestFactory.seedConversation(
            in: context.container,
            threadName: "Thread",
            isUnread: true
        )
        let manager = NotificationManagerTestFactory.makeManager(
            settingsService: service,
            modelContainer: context.container,
            isAppInForeground: true,
            activeConversationId: conversation.id,
            spy: spy
        )

        let expectation = expectation(description: "agent status notification")
        let observer = NotificationCenter.default.addObserver(
            forName: .agentStatusChanged,
            object: nil,
            queue: .main
        ) { notification in
            if notification.userInfo?["conversationId"] as? String == conversation.id {
                expectation.fulfill()
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        manager.markConversationRead(conversationId: conversation.id)

        wait(for: [expectation], timeout: 0.5)
    }
}

import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class NotificationForegroundTests: XCTestCase {
    func testHandleAppVisibilityChangedMarksActiveConversationReadAndRefreshesBadge() async throws {
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

        manager.handleAppVisibilityChanged()
        await manager.awaitPendingBadgeUpdate()

        XCTAssertFalse(
            NotificationManagerTestFactory.fetchConversation(id: conversation.id, in: context.container)?.isUnread ?? true
        )
        XCTAssertEqual(spy.dismissedConversationIds, [conversation.id])
        XCTAssertEqual(spy.badgeCounts.last, 0)
    }

    func testHandleAppVisibilityChangedSkipsMarkReadWhenAppNotInForeground() async throws {
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
            isAppInForeground: false,
            activeConversationId: conversation.id,
            spy: spy
        )

        manager.handleAppVisibilityChanged()
        await manager.awaitPendingBadgeUpdate()

        XCTAssertTrue(
            NotificationManagerTestFactory.fetchConversation(id: conversation.id, in: context.container)?.isUnread ?? false
        )
        XCTAssertTrue(spy.dismissedConversationIds.isEmpty)
        XCTAssertEqual(spy.badgeCounts.last, 1)
    }

    func testHandleAppVisibilityChangedJustRefreshesBadgeWhenNoActiveConversation() async throws {
        let service = InMemorySettingsService()
        let spy = NotificationSpy()
        let context = try NotificationManagerTestFactory.makeContext()
        _ = NotificationManagerTestFactory.seedConversation(
            in: context.container,
            threadName: "Thread",
            isUnread: true
        )
        let manager = NotificationManagerTestFactory.makeManager(
            settingsService: service,
            modelContainer: context.container,
            isAppInForeground: true,
            activeConversationId: nil,
            spy: spy
        )

        manager.handleAppVisibilityChanged()
        await manager.awaitPendingBadgeUpdate()

        XCTAssertTrue(spy.dismissedConversationIds.isEmpty)
        XCTAssertEqual(spy.badgeCounts.last, 1)
    }

    func testDidBecomeActiveNotificationTriggersMarkRead() throws {
        try assertObservedVisibilityEventMarksRead(notificationName: NSApplication.didBecomeActiveNotification)
    }

    func testOcclusionStateChangeWhileVisibleMarksRead() throws {
        try assertObservedVisibilityEventMarksRead(notificationName: NSApplication.didChangeOcclusionStateNotification)
    }

    func testOcclusionStateChangeWhenHiddenOnlyRefreshesBadge() throws {
        let service = InMemorySettingsService()
        let spy = NotificationSpy()
        let context = try NotificationManagerTestFactory.makeContext()
        let conversation = NotificationManagerTestFactory.seedConversation(
            in: context.container,
            threadName: "Thread",
            isUnread: true
        )
        let center = NotificationCenter()
        let manager = DefaultNotificationManager(
            settingsService: service,
            modelContainer: context.container,
            systemNotificationCenter: center
        )
        manager.isAppInForeground = { false }
        manager.setActiveConversationProvider { conversation.id }
        manager.onDismissDelivered = { spy.dismissedConversationIds.append($0) }

        let expectation = expectation(description: "badge count refreshed")
        var observedBadgeValues: [Int] = []
        manager.setBadgeCount = { count in
            observedBadgeValues.append(count)
            expectation.fulfill()
        }

        center.post(name: NSApplication.didChangeOcclusionStateNotification, object: nil)
        wait(for: [expectation], timeout: 0.5)

        XCTAssertTrue(spy.dismissedConversationIds.isEmpty)
        XCTAssertTrue(
            NotificationManagerTestFactory.fetchConversation(id: conversation.id, in: context.container)?.isUnread ?? false
        )
        XCTAssertEqual(observedBadgeValues.last, 1)
    }

    func testMinimizeThenEventThenUnminimizeMarksConversationRead() async throws {
        let service = InMemorySettingsService()
        let context = try NotificationManagerTestFactory.makeContext()
        let conversation = NotificationManagerTestFactory.seedConversation(
            in: context.container,
            threadName: "Thread"
        )
        let center = NotificationCenter()
        let manager = DefaultNotificationManager(
            settingsService: service,
            modelContainer: context.container,
            systemNotificationCenter: center
        )
        var inForeground = true
        manager.isAppInForeground = { inForeground }
        manager.setActiveConversationProvider { conversation.id }
        let dismissed = DismissalTracker()
        manager.onDismissDelivered = { dismissed.record($0) }
        manager.setBadgeCount = { _ in }
        manager.onPostNotification = { _, _, _ in }

        // Step 1: user is viewing the tab; agent finishes — no unread.
        manager.handleEvent(.stop(message: nil), conversationId: conversation.id)
        XCTAssertFalse(
            NotificationManagerTestFactory.fetchConversation(id: conversation.id, in: context.container)?.isUnread ?? true
        )

        // Step 2: user minimizes, agent finishes again.
        inForeground = false
        manager.handleEvent(.stop(message: nil), conversationId: conversation.id)
        XCTAssertTrue(
            NotificationManagerTestFactory.fetchConversation(id: conversation.id, in: context.container)?.isUnread ?? false
        )

        // Step 3: user un-minimizes — occlusion state change with app in foreground.
        inForeground = true
        let dismissExpectation = expectation(description: "notification dismissed after unminimize")
        dismissed.onRecord = { _ in
            dismissExpectation.fulfill()
        }
        center.post(name: NSApplication.didChangeOcclusionStateNotification, object: nil)
        await fulfillment(of: [dismissExpectation], timeout: 0.5)

        XCTAssertFalse(
            NotificationManagerTestFactory.fetchConversation(id: conversation.id, in: context.container)?.isUnread ?? true
        )
        XCTAssertEqual(dismissed.ids.last, conversation.id)
    }

    private func assertObservedVisibilityEventMarksRead(notificationName: Notification.Name) throws {
        let service = InMemorySettingsService()
        let context = try NotificationManagerTestFactory.makeContext()
        let conversation = NotificationManagerTestFactory.seedConversation(
            in: context.container,
            threadName: "Thread",
            isUnread: true
        )
        let center = NotificationCenter()
        let manager = DefaultNotificationManager(
            settingsService: service,
            modelContainer: context.container,
            systemNotificationCenter: center
        )
        manager.isAppInForeground = { true }
        manager.setActiveConversationProvider { conversation.id }

        let dismissExpectation = expectation(description: "conversation dismissed")
        var dismissed: [String] = []
        manager.onDismissDelivered = { id in
            dismissed.append(id)
            dismissExpectation.fulfill()
        }
        let badgeExpectation = expectation(description: "badge refreshed")
        var badgeValues: [Int] = []
        manager.setBadgeCount = { count in
            badgeValues.append(count)
            badgeExpectation.fulfill()
        }

        center.post(name: notificationName, object: nil)
        wait(for: [dismissExpectation, badgeExpectation], timeout: 0.5)

        XCTAssertFalse(
            NotificationManagerTestFactory.fetchConversation(id: conversation.id, in: context.container)?.isUnread ?? true
        )
        XCTAssertEqual(dismissed, [conversation.id])
        XCTAssertEqual(badgeValues.last, 0)
    }
}

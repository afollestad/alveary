import UserNotifications
import XCTest

@testable import Alveary

@MainActor
extension NotificationManagerTests {
    func testPRReviewReadyNotificationDeliversContextAndConversationRoute() async throws {
        let service = InMemorySettingsService()
        let spy = NotificationSpy()
        let context = try NotificationManagerTestFactory.makeContext()
        let conversation = NotificationManagerTestFactory.seedConversation(in: context.container, threadName: "PR Review")
        let manager = NotificationManagerTestFactory.makeManager(
            settingsService: service,
            modelContainer: context.container,
            isAppInForeground: false,
            activeConversationId: conversation.id,
            spy: spy
        )
        manager.onPostNotification = nil
        manager.notificationAuthorizationStatus = { .authorized }
        let delivered = expectation(description: "PR review notification delivered")
        var requests: [UNNotificationRequest] = []
        manager.addNotificationRequest = { request in
            requests.append(request)
            delivered.fulfill()
        }

        manager.handleEvent(.stop(message: "Your PR review is ready to confirm"), conversationId: conversation.id)
        await fulfillment(of: [delivered], timeout: 1)
        await manager.awaitPendingBadgeUpdate()

        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.identifier, conversation.id)
        XCTAssertEqual(request.content.title, "Alveary")
        XCTAssertEqual(request.content.body, "Your PR review is ready to confirm in \"PR Review\"")
        XCTAssertEqual(request.content.userInfo[NotificationUserInfoKey.conversationId] as? String, conversation.id)
        XCTAssertNotNil(request.content.sound)
        XCTAssertTrue(NotificationManagerTestFactory.fetchConversation(id: conversation.id, in: context.container)?.isUnread ?? false)
        XCTAssertEqual(spy.badgeCounts.last, 1)
    }
}

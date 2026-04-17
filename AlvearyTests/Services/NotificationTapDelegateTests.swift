import UserNotifications
import XCTest

@testable import Alveary

@MainActor
final class NotificationTapDelegateTests: XCTestCase {
    func testUserInfoKeyConstantMatchesNotificationManagerKey() {
        XCTAssertEqual(NotificationUserInfoKey.conversationId, "conversationId")
    }

    func testConversationIdReturnsValueForDefaultAction() {
        let id = NotificationTapDelegate.conversationId(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: [NotificationUserInfoKey.conversationId: "convo-7"]
        )
        XCTAssertEqual(id, "convo-7")
    }

    func testConversationIdIgnoresDismissAction() {
        let id = NotificationTapDelegate.conversationId(
            actionIdentifier: UNNotificationDismissActionIdentifier,
            userInfo: [NotificationUserInfoKey.conversationId: "convo-7"]
        )
        XCTAssertNil(id)
    }

    func testConversationIdIgnoresCustomAction() {
        let id = NotificationTapDelegate.conversationId(
            actionIdentifier: "custom-action",
            userInfo: [NotificationUserInfoKey.conversationId: "convo-7"]
        )
        XCTAssertNil(id)
    }

    func testConversationIdReturnsNilWhenUserInfoKeyMissing() {
        let id = NotificationTapDelegate.conversationId(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: [:]
        )
        XCTAssertNil(id)
    }

    func testConversationIdReturnsNilWhenUserInfoKeyHasWrongType() {
        let id = NotificationTapDelegate.conversationId(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: [NotificationUserInfoKey.conversationId: 42]
        )
        XCTAssertNil(id)
    }
}

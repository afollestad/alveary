import XCTest

@testable import Alveary

@MainActor
final class NotificationRouterTests: XCTestCase {
    func testRequestOpenSetsPending() {
        let router = NotificationRouter()
        router.requestOpen(conversationId: "abc")
        XCTAssertEqual(router.pendingConversationId, "abc")
    }

    func testClearPendingClearsMatchingID() {
        let router = NotificationRouter()
        router.requestOpen(conversationId: "abc")
        router.clearPendingIfMatches("abc")
        XCTAssertNil(router.pendingConversationId)
    }

    func testClearPendingIgnoresMismatchedID() {
        let router = NotificationRouter()
        router.requestOpen(conversationId: "abc")
        router.clearPendingIfMatches("zzz")
        XCTAssertEqual(router.pendingConversationId, "abc")
    }

    func testRequestOpenReplacesEarlierPending() {
        let router = NotificationRouter()
        router.requestOpen(conversationId: "first")
        router.requestOpen(conversationId: "second")
        XCTAssertEqual(router.pendingConversationId, "second")
    }
}

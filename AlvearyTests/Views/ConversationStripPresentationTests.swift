import XCTest

@testable import Alveary

final class ConversationStripPresentationTests: XCTestCase {
    func testUninitializedThreadWithOneConversationHidesStrip() {
        XCTAssertFalse(shouldShow(hasCompletedInitialSetup: false, conversationCount: 1))
    }

    func testUninitializedThreadWithMultipleConversationsHidesStrip() {
        XCTAssertFalse(shouldShow(hasCompletedInitialSetup: false, conversationCount: 2))
    }

    func testInitializedThreadWithOneConversationHidesStrip() {
        XCTAssertFalse(shouldShow(hasCompletedInitialSetup: true, conversationCount: 1))
    }

    func testInitializedThreadWithNoResolvedConversationsHidesStrip() {
        XCTAssertFalse(shouldShow(hasCompletedInitialSetup: true, conversationCount: 0))
    }

    func testInitializedThreadWithMultipleConversationsShowsStrip() {
        XCTAssertTrue(shouldShow(hasCompletedInitialSetup: true, conversationCount: 2))
    }

    private func shouldShow(hasCompletedInitialSetup: Bool, conversationCount: Int) -> Bool {
        ConversationStripPresentation.shouldShow(
            hasCompletedInitialSetup: hasCompletedInitialSetup,
            conversationCount: conversationCount
        )
    }
}

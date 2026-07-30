import XCTest

@testable import Alveary

/// The Overview timeline's follow-the-bottom policy: which readings keep the
/// reader parked at the end, and which timeline changes earn a scroll.
final class TimelineBottomFollowingTests: XCTestCase {
    private func followState(
        wasFollowing: Bool,
        contentGrew: Bool = false,
        distanceFromBottom: CGFloat
    ) -> Bool {
        TimelineBottomFollowing.nextFollowState(
            wasFollowing: wasFollowing,
            contentGrew: contentGrew,
            distanceFromBottom: distanceFromBottom
        )
    }

    func testExactBottomFollows() {
        XCTAssertTrue(followState(wasFollowing: false, distanceFromBottom: 0))
    }

    func testWithinSlackFollows() {
        // A fractional content height can leave the offset a hair short.
        XCTAssertTrue(followState(wasFollowing: false, distanceFromBottom: 6))
    }

    func testScrollingUpStopsFollowing() {
        XCTAssertFalse(followState(wasFollowing: true, distanceFromBottom: 400))
    }

    func testContentShorterThanContainerFollows() {
        // A negative distance means the content does not fill the pane.
        XCTAssertTrue(followState(wasFollowing: false, distanceFromBottom: -280))
    }

    func testContentGrowingBeneathAFollowerKeepsFollowing() {
        // The regression that broke this in the app: an appended row puts the
        // end below the viewport, which reads exactly like scrolling up. Treated
        // as opting out, the first append silently disabled every later one.
        XCTAssertTrue(followState(wasFollowing: true, contentGrew: true, distanceFromBottom: 120))
    }

    func testContentGrowingForANonFollowerDoesNotStartFollowing() {
        XCTAssertFalse(followState(wasFollowing: false, contentGrew: true, distanceFromBottom: 900))
    }

    func testAppendWhileFollowingScrolls() {
        XCTAssertTrue(
            TimelineBottomFollowing.shouldScrollToBottom(previousCount: 4, newCount: 5, isFollowing: true)
        )
    }

    func testAppendWhileScrolledUpDoesNotScroll() {
        XCTAssertFalse(
            TimelineBottomFollowing.shouldScrollToBottom(previousCount: 4, newCount: 5, isFollowing: false)
        )
    }

    func testFirstDetailDoesNotScroll() {
        // 0 -> N is the detail landing, not an append; the reader just opened
        // the pane and expects its header.
        XCTAssertFalse(
            TimelineBottomFollowing.shouldScrollToBottom(previousCount: 0, newCount: 12, isFollowing: true)
        )
    }

    func testDeletionDoesNotScroll() {
        XCTAssertFalse(
            TimelineBottomFollowing.shouldScrollToBottom(previousCount: 5, newCount: 4, isFollowing: true)
        )
    }
}

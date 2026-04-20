import XCTest

@testable import Alveary

@MainActor
final class ChatTranscriptScrollBehaviorTests: XCTestCase {
    // Content growth (e.g. bubble expand/collapse, streaming text wrap) must NOT trigger
    // preserve-follow re-scroll. `.defaultScrollAnchor(.bottom, for: .sizeChanges)` pins the
    // bottom during size changes, and the dedicated `events.count` / `streamingText` onChange
    // handlers snap to bottom when a new message or stream chunk arrives. Firing re-scrolls
    // on every intermediate animation frame of a bubble expand caused scroll jank.
    func testDoesNotPreserveFollowModeOnContentGrowthAlone() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 500, contentHeight: 1_000, containerHeight: 460)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 500, contentHeight: 1_040, containerHeight: 460)

        XCTAssertFalse(
            ChatTranscriptScrollBehavior.shouldPreserveFollowMode(
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
        )
    }

    func testDoesNotPreserveFollowModeWhenOffsetChangesWithContainerChange() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 500, contentHeight: 1_000, containerHeight: 460)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 470, contentHeight: 1_000, containerHeight: 360)

        XCTAssertFalse(
            ChatTranscriptScrollBehavior.shouldPreserveFollowMode(
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
        )
    }

    func testPreservesFollowModeWhenContainerHeightChangesAtBottomWithoutUserScroll() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_000, containerHeight: 460)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_000, containerHeight: 360)

        XCTAssertTrue(
            ChatTranscriptScrollBehavior.shouldPreserveFollowMode(
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
        )
    }

    func testCancelsProgrammaticScrollWhenUserMovesFurtherFromBottom() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_000, containerHeight: 400)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 470, contentHeight: 1_000, containerHeight: 400)

        XCTAssertTrue(
            ChatTranscriptScrollBehavior.shouldCancelProgrammaticScroll(
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
        )
    }

    func testDoesNotCancelProgrammaticScrollWhenOffsetMovesTowardBottom() {
        // Mid-flight `scrollTo` frames bump offsetY toward the bottom. These should never
        // be mistaken for a user drag.
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 200, contentHeight: 1_000, containerHeight: 400)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 560, contentHeight: 1_000, containerHeight: 400)

        XCTAssertFalse(
            ChatTranscriptScrollBehavior.shouldCancelProgrammaticScroll(
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
        )
    }

    func testReissuesPendingJumpToLatestWhenContainerShrinks() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_000, containerHeight: 460)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_000, containerHeight: 400)

        XCTAssertTrue(
            ChatTranscriptScrollBehavior.shouldReissuePendingJumpToLatest(
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
        )
    }

    func testReissuesPendingJumpToLatestWhenContentGrows() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_000, containerHeight: 460)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_080, containerHeight: 460)

        XCTAssertTrue(
            ChatTranscriptScrollBehavior.shouldReissuePendingJumpToLatest(
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
        )
    }

    func testDoesNotReissuePendingJumpToLatestWhenGeometryIsStable() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_000, containerHeight: 460)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 560, contentHeight: 1_000, containerHeight: 460)

        XCTAssertFalse(
            ChatTranscriptScrollBehavior.shouldReissuePendingJumpToLatest(
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
        )
    }

    func testDoesNotReissuePendingJumpToLatestWhenContainerGrows() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_000, containerHeight: 400)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_000, containerHeight: 460)

        XCTAssertFalse(
            ChatTranscriptScrollBehavior.shouldReissuePendingJumpToLatest(
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
        )
    }

    func testReissuesPendingPreserveFollowWhenContainerShrinks() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_000, containerHeight: 460)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_000, containerHeight: 400)

        XCTAssertTrue(
            ChatTranscriptScrollBehavior.shouldReissuePendingPreserveFollow(
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
        )
    }

    // Content growth is intentionally excluded so streaming / bubble-expand frames do not
    // re-issue `scrollTo` — `.defaultScrollAnchor(.bottom, for: .sizeChanges)` pins those,
    // and re-issuing here would re-introduce the bubble-expand jank the narrowing fixed.
    func testDoesNotReissuePendingPreserveFollowOnContentGrowth() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_000, containerHeight: 460)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_080, containerHeight: 460)

        XCTAssertFalse(
            ChatTranscriptScrollBehavior.shouldReissuePendingPreserveFollow(
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
        )
    }

    func testDoesNotReissuePendingPreserveFollowWhenContainerGrows() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_000, containerHeight: 400)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_000, containerHeight: 460)

        XCTAssertFalse(
            ChatTranscriptScrollBehavior.shouldReissuePendingPreserveFollow(
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
        )
    }
}

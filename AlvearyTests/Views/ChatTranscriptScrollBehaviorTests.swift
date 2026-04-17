import XCTest

@testable import Alveary

@MainActor
final class ChatTranscriptScrollBehaviorTests: XCTestCase {
    func testPreservesFollowModeWhenContentGrowsAtBottomWithoutUserScroll() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 500, contentHeight: 1_000, containerHeight: 460)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 500, contentHeight: 1_040, containerHeight: 460)

        XCTAssertTrue(
            ChatTranscriptScrollBehavior.shouldPreserveFollowMode(
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
        )
    }

    func testDoesNotPreserveFollowModeWhenOffsetChangesWithGrowth() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 500, contentHeight: 1_000, containerHeight: 460)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 470, contentHeight: 1_040, containerHeight: 460)

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

    func testReScrollOnPreserveFollowBypassesDebounceWhenContainerChanges() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 500, contentHeight: 1_000, containerHeight: 460)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 500, contentHeight: 1_000, containerHeight: 360)

        XCTAssertTrue(
            ChatTranscriptScrollBehavior.shouldReScrollOnPreserveFollow(
                oldMetrics: oldMetrics,
                newMetrics: newMetrics,
                timeSinceLastScroll: 0.01,
                debounce: 0.15
            )
        )
    }

    func testReScrollOnPreserveFollowSkipsWhenWithinDebounceAndContainerStable() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 500, contentHeight: 1_000, containerHeight: 460)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 500, contentHeight: 1_040, containerHeight: 460)

        XCTAssertFalse(
            ChatTranscriptScrollBehavior.shouldReScrollOnPreserveFollow(
                oldMetrics: oldMetrics,
                newMetrics: newMetrics,
                timeSinceLastScroll: 0.05,
                debounce: 0.15
            )
        )
    }

    func testReScrollOnPreserveFollowFiresWhenDebouncePasses() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 500, contentHeight: 1_000, containerHeight: 460)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 500, contentHeight: 1_040, containerHeight: 460)

        XCTAssertTrue(
            ChatTranscriptScrollBehavior.shouldReScrollOnPreserveFollow(
                oldMetrics: oldMetrics,
                newMetrics: newMetrics,
                timeSinceLastScroll: 0.2,
                debounce: 0.15
            )
        )
    }
}

import XCTest

@testable import Alveary

@MainActor
final class ChatTranscriptScrollBehaviorTests: XCTestCase {
    // Content growth (e.g. bubble expand/collapse, streaming text wrap) must NOT trigger
    // preserve-follow re-scroll. The AppKit container owns bottom anchoring during
    // row-height changes, and the dedicated `events.count` / `streamingText` onChange
    // handlers request bottom scrolls when a new message or stream chunk arrives.
    // Firing re-scrolls on every intermediate animation frame of a bubble expand
    // caused scroll jank.
    func testDoesNotPreserveFollowModeOnContentGrowthAlone() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 500, contentHeight: 1_000, containerHeight: 460)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 500, contentHeight: 1_040, containerHeight: 460)

        XCTAssertFalse(
            ChatTranscriptScrollBehavior.shouldPreserveFollowMode(
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
        )
        // Start at bottom so the geometry guard determines this result.
        XCTAssertFalse(ChatTranscriptScrollBehavior.shouldPreserveFollowMode(
            oldMetrics: .init(offsetY: 540, contentHeight: 1_000, containerHeight: 460),
            newMetrics: .init(offsetY: 540, contentHeight: 1_040, containerHeight: 460)
        ))
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
        // Start at bottom so the geometry guard determines this result.
        XCTAssertFalse(ChatTranscriptScrollBehavior.shouldPreserveFollowMode(
            oldMetrics: .init(offsetY: 540, contentHeight: 1_000, containerHeight: 460),
            newMetrics: .init(offsetY: 510, contentHeight: 1_000, containerHeight: 360)
        ))
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

    // REGRESSION: error banners and other composer-panel content can appear while
    // a thread is visible, shrinking the transcript's viewport. When that happens
    // with the user at bottom, the AppKit scroll owner can bump offsetY *up* to
    // keep the content-bottom aligned to the viewport-bottom — so offsetY CHANGED
    // but the user didn't scroll. The old `!offsetChanged` guard excluded this case
    // and left the transcript above the bottom once the banner appeared.
    // `!offsetDecreased` correctly allows owner-driven offset increases while
    // still rejecting real user drags.
    func testPreservesFollowModeOnContainerShrinkWithAnchorDrivenOffsetIncrease() {
        // Was at bottom (distance=0), container shrinks by 100, anchor bumps offsetY
        // from 540 to 640 to keep content-bottom at viewport-bottom.
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_000, containerHeight: 460)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 640, contentHeight: 1_000, containerHeight: 360)

        XCTAssertTrue(
            ChatTranscriptScrollBehavior.shouldPreserveFollowMode(
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
        )
    }

    // Container growth is not what preserve-follow is for — a growing viewport
    // pulls the user toward the bottom on its own.
    func testDoesNotPreserveFollowModeOnContainerGrowth() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_000, containerHeight: 360)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_000, containerHeight: 460)

        XCTAssertFalse(
            ChatTranscriptScrollBehavior.shouldPreserveFollowMode(
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
        )
        // Start at bottom so the geometry guard determines this result.
        XCTAssertFalse(ChatTranscriptScrollBehavior.shouldPreserveFollowMode(
            oldMetrics: .init(offsetY: 640, contentHeight: 1_000, containerHeight: 360),
            newMetrics: .init(offsetY: 640, contentHeight: 1_000, containerHeight: 460)
        ))
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

    // Cancel-predicate regression tests covering programmatic scroll false
    // positives live in `ChatTranscriptScrollBehaviorTests+CancelGuards.swift`.

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

    // `.preserveFollow` has no content-growth reissue case, so `isAtBottom` means
    // the pending scroll has landed and the mode can clear.
    func testPendingScrollActionPreserveFollowClearsOnIsAtBottom() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 200, contentHeight: 1_000, containerHeight: 400)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 600, contentHeight: 1_000, containerHeight: 400)

        XCTAssertEqual(
            ChatTranscriptScrollBehavior.pendingScrollAction(
                pending: .preserveFollow,
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            ),
            .settleFollowingAndClear
        )
    }

    // REGRESSION: row-height settling can briefly report `isAtBottom` before the
    // AppKit document view has published all final heights. If `.jumpToLatest`
    // cleared on this transient `isAtBottom`, the reissue loop would disarm and
    // the viewport could be left above the actual bottom. Instead we mark as
    // following but keep the mode live so subsequent content growth re-enters
    // `shouldReissuePendingJumpToLatest`.
    func testPendingScrollActionJumpToLatestKeepsPendingOnIsAtBottom() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 200, contentHeight: 1_000, containerHeight: 400)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 600, contentHeight: 1_000, containerHeight: 400)

        XCTAssertEqual(
            ChatTranscriptScrollBehavior.pendingScrollAction(
                pending: .jumpToLatest,
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            ),
            .followWithoutClearing
        )
    }

    func testPendingScrollActionCancelsOnUserDragAway() {
        // Offset moved up (away from bottom) by more than the 0.5pt threshold.
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_000, containerHeight: 400)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 470, contentHeight: 1_000, containerHeight: 400)

        XCTAssertEqual(
            ChatTranscriptScrollBehavior.pendingScrollAction(
                pending: .jumpToLatest,
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            ),
            .cancelled
        )
    }

    // The old `offsetChanged` guard incorrectly cancelled this anchor catch-up:
    // distance grows while offset increases. Cancellation must require offsetDecreased.
    // A `.jumpToLatest` pending scroll during streaming should NOT cancel when the
    // AppKit owner is catching up to content growth (offsetY increasing toward
    // bottom, content grew by more). It should reissue instead.
    func testPendingScrollActionReissuesOnAnchorCatchUpDuringJumpToLatest() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 600, contentHeight: 1_000, containerHeight: 400)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 620, contentHeight: 1_100, containerHeight: 400)

        XCTAssertEqual(
            ChatTranscriptScrollBehavior.pendingScrollAction(
                pending: .jumpToLatest,
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            ),
            .reissue
        )
    }

    // Same scenario under `.preserveFollow` resolves to `.noop` (content growth is
    // intentionally excluded from preserveFollow's reissue predicate; the AppKit
    // owner handles it).
    func testPendingScrollActionNoopsOnAnchorCatchUpDuringPreserveFollow() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 600, contentHeight: 1_000, containerHeight: 400)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 620, contentHeight: 1_100, containerHeight: 400)

        XCTAssertEqual(
            ChatTranscriptScrollBehavior.pendingScrollAction(
                pending: .preserveFollow,
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            ),
            .noop
        )
    }

    // `shouldCancelProgrammaticScroll` must apply to both pending modes, not just
    // `.jumpToLatest`. Pins that a user drag during a `.preserveFollow` (container-
    // shrink-initiated) pending scroll also cancels instead of falling through to the
    // mode-specific reissue branch. Guards against a future refactor that accidentally
    // pushes the cancel check inside the pending-mode switch.
    func testPendingScrollActionCancelsPreserveFollowOnUserDragAway() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_000, containerHeight: 400)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 470, contentHeight: 1_000, containerHeight: 400)

        XCTAssertEqual(
            ChatTranscriptScrollBehavior.pendingScrollAction(
                pending: .preserveFollow,
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            ),
            .cancelled
        )
    }

    func testPendingScrollActionReissuesJumpToLatestOnContentGrowth() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_000, containerHeight: 460)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_080, containerHeight: 460)

        XCTAssertEqual(
            ChatTranscriptScrollBehavior.pendingScrollAction(
                pending: .jumpToLatest,
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            ),
            .reissue
        )
    }

    // `.preserveFollow` intentionally does not react to content growth — that
    // AppKit owns row-height anchoring; reissuing on streaming or bubble-expand
    // frames would re-introduce scroll jank.
    func testPendingScrollActionPreserveFollowIgnoresContentGrowth() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_000, containerHeight: 460)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_080, containerHeight: 460)

        XCTAssertEqual(
            ChatTranscriptScrollBehavior.pendingScrollAction(
                pending: .preserveFollow,
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            ),
            .noop
        )
    }

    func testPendingScrollActionReissuesPreserveFollowOnContainerShrink() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_000, containerHeight: 460)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_000, containerHeight: 400)

        XCTAssertEqual(
            ChatTranscriptScrollBehavior.pendingScrollAction(
                pending: .preserveFollow,
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            ),
            .reissue
        )
    }

    // REGRESSION: streaming chunks can make `contentHeight` jump by >60pt in a
    // single render pass before AppKit row-height anchoring bumps `offsetY`. A
    // naive `isFollowing = isNearBottom` on that tick would flip follow mode off
    // mid-stream (offset didn't move — user didn't scroll), which then disarms
    // follow-mode preservation and makes the jump-to-bottom button flicker.
    // `nextFollowingState` must hold the line and leave `isFollowing` alone.
    func testNextFollowingStateKeepsFollowingOnContentGrowthWithoutUserScroll() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_000, containerHeight: 460)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_120, containerHeight: 460)
        // Distance jumped from 0 to 120 — not near bottom — but the user didn't scroll.

        XCTAssertTrue(
            ChatTranscriptScrollBehavior.nextFollowingState(
                currentIsFollowing: true,
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
        )
    }

    func testNextFollowingStateSettlesToTrueWhenNearBottom() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 300, contentHeight: 1_000, containerHeight: 460)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 560, contentHeight: 1_000, containerHeight: 460)
        // Distance shrunk from 240 → -20 (≈ near bottom).

        XCTAssertTrue(
            ChatTranscriptScrollBehavior.nextFollowingState(
                currentIsFollowing: false,
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
        )
    }

    func testNextFollowingStateDropsFollowingOnUserScrollAway() {
        // User drags up — offset decreased, distance grew.
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 540, contentHeight: 1_000, containerHeight: 400)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 380, contentHeight: 1_000, containerHeight: 400)

        XCTAssertFalse(
            ChatTranscriptScrollBehavior.nextFollowingState(
                currentIsFollowing: true,
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
        )
    }

    func testNextFollowingStateDropsFollowingOnSmallUserScrollAway() {
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 600, contentHeight: 1_000, containerHeight: 400)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 584, contentHeight: 1_000, containerHeight: 400)
        // Distance grew from 0 to 16pt. This is enough visible separation from
        // bottom for the composer divider and jump-to-latest button to appear.

        XCTAssertFalse(
            ChatTranscriptScrollBehavior.nextFollowingState(
                currentIsFollowing: true,
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
        )
    }

    func testNextFollowingStatePassesThroughWhenAmbiguous() {
        // Neither near bottom nor a user drag away: not enough signal to flip.
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 200, contentHeight: 1_000, containerHeight: 460)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 200, contentHeight: 1_000, containerHeight: 460)

        XCTAssertFalse(
            ChatTranscriptScrollBehavior.nextFollowingState(
                currentIsFollowing: false,
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
        )
        XCTAssertTrue(
            ChatTranscriptScrollBehavior.nextFollowingState(
                currentIsFollowing: true,
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
        )
    }

    func testPendingScrollActionNoopOnStableGeometry() {
        // Tiny offset adjustment toward the bottom (not user drag, not content
        // growth, not `isAtBottom`). With `.jumpToLatest`, the near-bottom
        // backstop kicks in — this covers the preserveFollow case where the
        // backstop is intentionally *not* applied, so the mode is left alone.
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 200, contentHeight: 1_000, containerHeight: 460)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 201, contentHeight: 1_000, containerHeight: 460)

        XCTAssertEqual(
            ChatTranscriptScrollBehavior.pendingScrollAction(
                pending: .preserveFollow,
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            ),
            .noop
        )
    }
}

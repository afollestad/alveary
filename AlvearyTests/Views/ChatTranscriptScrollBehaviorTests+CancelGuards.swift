import XCTest

@testable import Alveary

// `shouldCancelProgrammaticScroll` is a "should this user-drag-like tick actually
// cancel a pending programmatic scroll?" predicate. It must let real user drags
// through while rejecting the several SwiftUI-initiated geometry changes that
// happen to *look* like drags. Each regression test below pins one false-positive
// pathway with metrics taken verbatim from instrumented live runs — do not relax
// the guards without a replacement for the scenario captured here.
extension ChatTranscriptScrollBehaviorTests {
    // REGRESSION: at turn-end, `forceFullRebuild` regenerates tool-group
    // identities with new UUIDs; SwiftUI's ForEach diffs the list as heavy
    // remove+insert, so `.defaultScrollAnchor(.bottom, for: .sizeChanges)` loses
    // its anchor view mid-diff and the ScrollView snaps offsetY to a stale value
    // in a single geometry tick. The observed drop was 347pt in 1ms
    // (off=893 dist=0 → off=546 dist=347), which no user can produce with a
    // drag. The pre-guard predicate fired cancel here (distance=347 is clearly
    // past near-bottom), flipping `isFollowing` to false right as the turn ended
    // and the jump-to-latest button appeared. A per-tick velocity cap rejects
    // programmatic disturbances while still honoring plausible user drags.
    func testDoesNotCancelProgrammaticScrollOnTurnEndRebuildDisturbance() {
        // offsetY snaps from 893 to 546 in a single tick — the rebuild's row
        // identity churn lost the anchor view.
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 893, contentHeight: 1_486, containerHeight: 593)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 546, contentHeight: 1_486, containerHeight: 593)

        XCTAssertFalse(
            ChatTranscriptScrollBehavior.shouldCancelProgrammaticScroll(
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
        )
    }

    // REGRESSION: during streaming when content is SMALLER than the viewport,
    // `.scrollPosition(anchor: .bottom)` pins content to the viewport-bottom by
    // setting `offsetY` to a negative value. A programmatic `scrollTo(edge: .bottom)`
    // in that state causes a large offsetY swing (e.g. 0 → -377) that looks like a
    // user drag per `offsetDecreased && movedFurtherFromBottom`, but the new
    // `distanceFromBottom` lands within the near-bottom band (e.g. 12pt). The
    // pre-fix cancel fired in that case, flipping `isFollowing` to false and
    // flashing the jump-to-latest button mid-stream — user-visible symptom:
    // "the button briefly appeared towards the end" of a long streaming response.
    // The fix requires the new position to be clearly past near-bottom before
    // honoring the cancel signal.
    func testDoesNotCancelProgrammaticScrollOnAnchorAdjustmentDuringStreaming() {
        // From observed log: content (228) < viewport (593), `scrollTo(edge: .bottom)`
        // swings offsetY from 0 to -377 while pinning content to viewport-bottom.
        // New distance = 12 — well within `isNearBottom`.
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 0, contentHeight: 228, containerHeight: 593)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: -377, contentHeight: 228, containerHeight: 593)

        XCTAssertFalse(
            ChatTranscriptScrollBehavior.shouldCancelProgrammaticScroll(
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
        )
    }

    // REGRESSION: during streaming, `.defaultScrollAnchor(.bottom, for: .sizeChanges)`
    // catches up to content growth by *increasing* offsetY, but if content grew by
    // more than the anchor bumped on the same tick, `distanceFromBottom` also grows.
    // The old `offsetChanged && movedFurtherFromBottom` check read that as a user
    // drag and tripped `.cancelled`, briefly flipping `isFollowing` to false and
    // flashing the jump-to-latest button mid-stream. A user drag decreases offsetY;
    // anchor catch-up increases it — requiring `offsetDecreased` fixes this.
    func testDoesNotCancelProgrammaticScrollOnAnchorCatchUpDuringStreaming() {
        // offsetY increased (anchor catch-up toward bottom), distance grew
        // (content grew by more than the catch-up).
        let oldMetrics = ChatTranscriptScrollMetrics(offsetY: 600, contentHeight: 1_000, containerHeight: 400)
        let newMetrics = ChatTranscriptScrollMetrics(offsetY: 620, contentHeight: 1_100, containerHeight: 400)

        XCTAssertFalse(
            ChatTranscriptScrollBehavior.shouldCancelProgrammaticScroll(
                oldMetrics: oldMetrics,
                newMetrics: newMetrics
            )
        )
    }
}

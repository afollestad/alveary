import SwiftUI
import XCTest

@testable import Alveary

/// The restore policy behind `restoresScrollOffset(_:position:token:)`. Every screen it drives
/// unmounts entirely when the sidebar selection changes, so a wrong answer here is either a list
/// that forgets where it was or one that yanks the reader somewhere they did not ask for.
@MainActor
final class ScrollOffsetRestorationTests: XCTestCase {
    private func makeReading(
        offset: CGFloat = 0,
        contentHeight: CGFloat = 2_000,
        containerHeight: CGFloat = 500
    ) -> ScrollOffsetReading {
        ScrollOffsetReading(
            offset: offset,
            contentHeight: contentHeight,
            containerHeight: containerHeight
        )
    }

    // MARK: - Store

    func testStoreOffersNothingUntilSomethingIsRecorded() {
        let store = ScrollOffsetStore()

        XCTAssertNil(store.restorableOffset(for: nil))
    }

    func testStoreOffersARecordedOffsetBackForTheSameToken() {
        let store = ScrollOffsetStore()
        store.record(offset: 420, token: nil)

        XCTAssertEqual(store.restorableOffset(for: nil), 420)
    }

    /// A tabbed screen keeps its documented "each result set starts at the top" behavior through
    /// this check alone, since its scroll view is keyed by the selection and remounts on a switch.
    func testStoreOffersNothingForADifferentToken() {
        let store = ScrollOffsetStore()
        store.record(offset: 420, token: PullRequestsFilter.all)

        XCTAssertNil(store.restorableOffset(for: PullRequestsFilter.reviewing))
        XCTAssertEqual(store.restorableOffset(for: PullRequestsFilter.all), 420)
    }

    /// A screen left at the top has nothing to restore, so it must not sit in `.wait` forever
    /// holding off the recording that keeps the token current.
    func testStoreOffersNothingWhenTheScreenWasLeftAtTheTop() {
        let store = ScrollOffsetStore()
        store.record(offset: 0, token: nil)

        XCTAssertNil(store.restorableOffset(for: nil))
    }

    /// Elastic scrolling reports a negative offset while the content bounces past the top; storing
    /// one unclamped would read back as "left at the top" and silently drop the restore.
    func testStoreClampsAnElasticBounceToTheTop() {
        let store = ScrollOffsetStore()
        store.record(offset: -40, token: nil)

        XCTAssertEqual(store.offset, 0)
        XCTAssertNil(store.restorableOffset(for: nil))
    }

    // MARK: - Policy

    func testADegenerateReadingIsIgnoredRatherThanRecorded() {
        let step = ScrollOffsetRestorationStep.next(
            reading: makeReading(contentHeight: 0, containerHeight: 0),
            hasSettled: true,
            restorableOffset: nil
        )

        XCTAssertEqual(step, .ignore)
    }

    func testNothingToRestoreRecordsImmediately() {
        let step = ScrollOffsetRestorationStep.next(
            reading: makeReading(offset: 120),
            hasSettled: false,
            restorableOffset: nil
        )

        XCTAssertEqual(step, .record)
    }

    func testASettledScreenKeepsRecordingRatherThanRestoringAgain() {
        let step = ScrollOffsetRestorationStep.next(
            reading: makeReading(offset: 300),
            hasSettled: true,
            restorableOffset: 900
        )

        XCTAssertEqual(step, .record)
    }

    func testTallEnoughContentRestoresTheStoredOffset() {
        let step = ScrollOffsetRestorationStep.next(
            reading: makeReading(contentHeight: 2_000, containerHeight: 500),
            hasSettled: false,
            restorableOffset: 900
        )

        XCTAssertEqual(step, .restore(900))
    }

    /// The screen mounts before its rows land — Pull Requests mounts on `.loading` — and scrolling
    /// against the short layout would clamp to the current end and count itself done.
    func testShortContentWaitsInsteadOfClampingToTheCurrentEnd() {
        let waiting = ScrollOffsetRestorationStep.next(
            reading: makeReading(contentHeight: 600, containerHeight: 500),
            hasSettled: false,
            restorableOffset: 900
        )
        XCTAssertEqual(waiting, .wait)

        // Once the rows land the offset is reachable and the restore fires. This is also the
        // boundary: 1400 - 500 is exactly 900, and exactly reachable must count as reachable or a
        // list restored to its own end would wait forever.
        let grown = ScrollOffsetRestorationStep.next(
            reading: makeReading(contentHeight: 1_400, containerHeight: 500),
            hasSettled: false,
            restorableOffset: 900
        )
        XCTAssertEqual(grown, .restore(900))
    }

    /// A reader who scrolled while the content was still growing keeps their position; the pending
    /// restore is abandoned rather than yanking the view.
    func testAReaderScrollingFirstAbandonsThePendingRestore() {
        let step = ScrollOffsetRestorationStep.next(
            reading: makeReading(offset: 40, contentHeight: 600, containerHeight: 500),
            hasSettled: false,
            restorableOffset: 900
        )

        XCTAssertEqual(step, .settle)
    }
}

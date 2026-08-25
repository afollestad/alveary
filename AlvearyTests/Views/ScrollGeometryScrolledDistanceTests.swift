import SwiftUI
import XCTest

@testable import Alveary

/// Covers the inset correction every scroll-gated hairline in the app reads through.
///
/// Unit-tested rather than left to the snapshot suite for the reason the compact settings
/// navigation's gate is: nothing scrolls a baseline, so those surfaces can only ever record the
/// resting state — and a wrong reading is invisible there while being wrong everywhere else.
final class ScrollGeometryScrolledDistanceTests: XCTestCase {
    /// A pane-sized scroll view with content taller and wider than it, so no reading is clamped
    /// by content that fits. Explicitly typed and built once per call rather than nested into the
    /// assertions, for the type-check budget (see `Alveary/Views/AGENTS.md`).
    private func geometry(offsetX: CGFloat = 0, offsetY: CGFloat = 0, insets: EdgeInsets) -> ScrollGeometry {
        let contentOffset = CGPoint(x: offsetX, y: offsetY)
        let contentSize = CGSize(width: 1200, height: 4000)
        let containerSize = CGSize(width: 420, height: 600)
        return ScrollGeometry(
            contentOffset: contentOffset,
            contentSize: contentSize,
            contentInsets: insets,
            containerSize: containerSize
        )
    }

    private func insets(top: CGFloat = 0, leading: CGFloat = 0) -> EdgeInsets {
        EdgeInsets(top: top, leading: leading, bottom: 0, trailing: 0)
    }

    func testRestingUnderATopInsetReadsAsAtTheTop() {
        let resting = geometry(offsetY: -24, insets: insets(top: 24))
        XCTAssertEqual(resting.verticalScrolledDistance, 0)
        XCTAssertFalse(resting.isScrolledFromTop)
    }

    /// The reading the raw offset gets wrong: a scroll view with a top inset reaches
    /// `contentOffset.y == 0` only after the content has already travelled the inset's height, so
    /// gating on the raw offset hides the chrome exactly when it is first owed.
    func testScrollingByTheInsetHeightReadsAsScrolled() {
        let scrolled = geometry(offsetY: 0, insets: insets(top: 24))
        XCTAssertEqual(scrolled.verticalScrolledDistance, 24)
        XCTAssertTrue(scrolled.isScrolledFromTop)
    }

    func testElasticOverscrollPastTheTopReadsAsAtTheTop() {
        let overscrolled = geometry(offsetY: -64, insets: insets(top: 24))
        XCTAssertEqual(overscrolled.verticalScrolledDistance, -40)
        XCTAssertFalse(overscrolled.isScrolledFromTop)
    }

    /// The slack the threshold carries: a fractional resting offset is a layout artifact, not a
    /// reader scrolling, and gating on `> 0` alone would flicker the chrome on at rest.
    func testFractionalRestingOffsetReadsAsAtTheTop() {
        XCTAssertFalse(geometry(offsetY: 0.25, insets: insets()).isScrolledFromTop)
        XCTAssertTrue(geometry(offsetY: 1, insets: insets()).isScrolledFromTop)
    }

    /// The horizontal twin corrects its own axis the same way — the chip strips' gate, whose
    /// leading inset is what defeated the raw offset on the compact settings navigation.
    func testHorizontalDistanceCorrectsTheLeadingInset() {
        XCTAssertEqual(geometry(offsetX: -280, insets: insets(leading: 280)).horizontalScrolledDistance, 0)
        XCTAssertEqual(geometry(offsetX: 0, insets: insets(leading: 280)).horizontalScrolledDistance, 280)
    }
}

import XCTest

@testable import Alveary

/// Covers the compact settings navigation's trailing-divider gating.
///
/// This math is deliberately unit-tested rather than left to the snapshot suite: nothing scrolls a
/// baseline, so `settings_screen_compact_navigation_overflow` can only ever record the resting
/// state — and every wrong version of this gate so far has read correctly there.
@MainActor
final class SettingsScreenCompactNavigationTests: XCTestCase {
    /// The strip's trailing sentinel matches the detail column's inset.
    private let sentinel = SettingsScreenLayout.settingsContentInset

    private func geometry(content: CGFloat, container: CGFloat, scrolled: CGFloat) -> SettingsCompactNavigationScrollGeometry {
        SettingsCompactNavigationScrollGeometry(contentWidth: content, containerWidth: container, scrolledDistance: scrolled)
    }

    func testNoDividerWhenEveryChipFits() {
        XCTAssertFalse(geometry(content: 400, container: 620, scrolled: 0).hasChipsBehindTrailingEdge)
    }

    /// A strip whose chips fit and whose only overflow is the sentinel has nothing hidden, so the
    /// divider would be pure noise.
    func testNoDividerWhenOnlyTheSentinelOverflows() {
        XCTAssertFalse(geometry(content: 620 + sentinel, container: 620, scrolled: 0).hasChipsBehindTrailingEdge)
    }

    func testDividerAtRestWhenChipsOverflow() {
        XCTAssertTrue(geometry(content: 881, container: 620, scrolled: 0).hasChipsBehindTrailingEdge)
    }

    func testDividerMidScroll() {
        XCTAssertTrue(geometry(content: 881, container: 620, scrolled: 62).hasChipsBehindTrailingEdge)
    }

    /// At the end the sentinel is the only thing left to scroll, so the last chip is fully
    /// visible and the divider must clear.
    func testNoDividerAtScrollEnd() {
        let maxScroll: CGFloat = 881 - 620

        XCTAssertFalse(geometry(content: 881, container: 620, scrolled: maxScroll).hasChipsBehindTrailingEdge)
    }

    /// Rubber-banding past either end must not flip the divider to the wrong state.
    func testNoDividerWhenOverscrolledPastTheEnd() {
        XCTAssertFalse(geometry(content: 881, container: 620, scrolled: 300).hasChipsBehindTrailingEdge)
    }

    func testDividerSurvivesOverscrollBeforeTheStart() {
        XCTAssertTrue(geometry(content: 881, container: 620, scrolled: -15).hasChipsBehindTrailingEdge)
    }

    /// The dimensions measured in the running app, where the strip's scrollable distance (461)
    /// exceeds the 280pt leading content inset it inherits from the split-view detail column.
    ///
    /// That combination is what defeated the gate this surface shipped with: `contentOffset.x` ran
    /// −280 at rest to **+181** at the end, so comparing the raw offset against the scrollable
    /// distance was true at both, and `abs()` was too. Only feeding these assertions the
    /// inset-corrected distance makes them disagree the way the two positions actually differ —
    /// `ScrollGeometry.horizontalScrolledDistance` is what produces it.
    func testGatingAtTheDimensionsThatDefeatedTheRawOffset() {
        let content: CGFloat = 881
        let container: CGFloat = 420

        XCTAssertTrue(geometry(content: content, container: container, scrolled: 0).hasChipsBehindTrailingEdge)
        XCTAssertFalse(
            geometry(content: content, container: container, scrolled: content - container).hasChipsBehindTrailingEdge
        )
    }
}

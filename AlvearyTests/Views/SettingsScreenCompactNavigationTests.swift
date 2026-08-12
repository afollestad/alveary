import XCTest

@testable import Alveary

/// Covers the compact settings navigation's trailing-divider gating.
///
/// This math is deliberately unit-tested rather than left to the snapshot suite: scroll geometry
/// publishes *after* a baseline displays, so `settings_screen_compact_navigation_overflow` never
/// captures the divider at all, whatever the strip's scroll position.
@MainActor
final class SettingsScreenCompactNavigationTests: XCTestCase {
    /// The strip's trailing sentinel matches the detail column's inset.
    private let sentinel = SettingsScreenLayout.settingsContentInset

    private func geometry(content: CGFloat, container: CGFloat, offset: CGFloat) -> SettingsCompactNavigationScrollGeometry {
        SettingsCompactNavigationScrollGeometry(contentWidth: content, containerWidth: container, contentOffset: offset)
    }

    func testNoDividerWhenEveryChipFits() {
        XCTAssertFalse(geometry(content: 400, container: 620, offset: 0).hasChipsBehindTrailingEdge)
    }

    /// A strip whose chips fit and whose only overflow is the sentinel has nothing hidden, so the
    /// divider would be pure noise.
    func testNoDividerWhenOnlyTheSentinelOverflows() {
        XCTAssertFalse(geometry(content: 620 + sentinel, container: 620, offset: 0).hasChipsBehindTrailingEdge)
    }

    func testDividerAtRestWhenChipsOverflow() {
        XCTAssertTrue(geometry(content: 881, container: 620, offset: 0).hasChipsBehindTrailingEdge)
    }

    func testDividerMidScroll() {
        XCTAssertTrue(geometry(content: 881, container: 620, offset: -199).hasChipsBehindTrailingEdge)
    }

    /// At the end the sentinel is the only thing left to scroll, so the last chip is fully
    /// visible and the divider must clear.
    func testNoDividerAtScrollEnd() {
        let maxScroll: CGFloat = 881 - 620

        XCTAssertFalse(geometry(content: 881, container: 620, offset: -maxScroll).hasChipsBehindTrailingEdge)
    }

    /// Rubber-banding past either end must not flip the divider back on.
    func testNoDividerWhenOverscrolledPastTheEnd() {
        XCTAssertFalse(geometry(content: 881, container: 620, offset: -300).hasChipsBehindTrailingEdge)
    }

    func testDividerSurvivesOverscrollBeforeTheStart() {
        XCTAssertTrue(geometry(content: 881, container: 620, offset: 15).hasChipsBehindTrailingEdge)
    }

    /// The regression guard for the bug this gate was first written with: the strip reports
    /// `contentOffset.x` as 0 at rest down to *minus* the scrollable distance at the end, so a
    /// gate that compared the raw offset against a positive threshold was true everywhere and
    /// pinned the divider on permanently. Reading the magnitude makes both conventions agree.
    func testGatingIsIndependentOfTheOffsetSignConvention() {
        for distance in stride(from: CGFloat(0), through: 261, by: 29) {
            XCTAssertEqual(
                geometry(content: 881, container: 620, offset: -distance).hasChipsBehindTrailingEdge,
                geometry(content: 881, container: 620, offset: distance).hasChipsBehindTrailingEdge,
                "divider gating disagreed between offset -\(distance) and +\(distance)"
            )
        }
    }
}

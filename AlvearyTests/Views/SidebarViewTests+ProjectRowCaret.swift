import XCTest

@testable import Alveary

@MainActor
extension SidebarViewTests {
    func testCaretFlashesOnlyWhenThePointerIsAway() {
        XCTAssertTrue(
            sidebarProjectCaretFlashesOnExpansionChange(isHovering: false, suppressHoverAffordances: false)
        )
        XCTAssertFalse(
            sidebarProjectCaretFlashesOnExpansionChange(isHovering: true, suppressHoverAffordances: false)
        )
    }

    func testCaretDoesNotFlashWhileHoverAffordancesAreSuppressed() {
        XCTAssertFalse(
            sidebarProjectCaretFlashesOnExpansionChange(isHovering: false, suppressHoverAffordances: true)
        )
    }

    func testFlashShowsTheCaretWithoutHover() {
        XCTAssertTrue(
            sidebarProjectDisclosureCaretIsVisible(
                isHovering: false,
                isFlashing: true,
                suppressHoverAffordances: false
            )
        )
        XCTAssertFalse(
            sidebarProjectDisclosureCaretIsVisible(
                isHovering: false,
                isFlashing: false,
                suppressHoverAffordances: false
            )
        )
    }

    // A caret visible mid-drag would both add hover chrome the drag suppresses and become a click
    // target competing with the drop.
    func testDragSuppressionHidesTheCaretRegardlessOfHoverOrFlash() {
        for isHovering in [true, false] {
            for isFlashing in [true, false] {
                XCTAssertFalse(
                    sidebarProjectDisclosureCaretIsVisible(
                        isHovering: isHovering,
                        isFlashing: isFlashing,
                        suppressHoverAffordances: true
                    ),
                    "hovering: \(isHovering), flashing: \(isFlashing)"
                )
            }
        }
    }
}

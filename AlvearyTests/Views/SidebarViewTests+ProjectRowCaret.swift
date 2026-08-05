import XCTest

@testable import Alveary

@MainActor
extension SidebarViewTests {
    func testCaretFlashesOnlyWhenThePointerIsAway() {
        XCTAssertTrue(
            sidebarDisclosureCaretFlashesOnExpansionChange(isHovering: false, suppressHoverAffordances: false)
        )
        XCTAssertFalse(
            sidebarDisclosureCaretFlashesOnExpansionChange(isHovering: true, suppressHoverAffordances: false)
        )
    }

    func testCaretDoesNotFlashWhileHoverAffordancesAreSuppressed() {
        XCTAssertFalse(
            sidebarDisclosureCaretFlashesOnExpansionChange(isHovering: false, suppressHoverAffordances: true)
        )
    }

    func testFlashShowsTheCaretWithoutHover() {
        XCTAssertTrue(
            sidebarDisclosureCaretIsVisible(
                isExpanded: true,
                isHovering: false,
                isFlashing: true,
                suppressHoverAffordances: false
            )
        )
        XCTAssertFalse(
            sidebarDisclosureCaretIsVisible(
                isExpanded: true,
                isHovering: false,
                isFlashing: false,
                suppressHoverAffordances: false
            )
        )
    }

    // An expanded row's caret is hover chrome, and a caret visible mid-drag would both add chrome
    // the drag suppresses and become a click target competing with the drop.
    func testDragSuppressionHidesTheExpandedCaretRegardlessOfHoverOrFlash() {
        for isHovering in [true, false] {
            for isFlashing in [true, false] {
                XCTAssertFalse(
                    sidebarDisclosureCaretIsVisible(
                        isExpanded: true,
                        isHovering: isHovering,
                        isFlashing: isFlashing,
                        suppressHoverAffordances: true
                    ),
                    "hovering: \(isHovering), flashing: \(isFlashing)"
                )
            }
        }
    }

    // A collapsed row's caret is the only sign it hides content, so it survives every reason an
    // expanded row would drop it — including a drag, whose toggle guard leaves the caret inert.
    func testCollapsedCaretStaysVisibleWithoutHoverFlashOrDragSuppression() {
        for isHovering in [true, false] {
            for isFlashing in [true, false] {
                for suppressHoverAffordances in [true, false] {
                    XCTAssertTrue(
                        sidebarDisclosureCaretIsVisible(
                            isExpanded: false,
                            isHovering: isHovering,
                            isFlashing: isFlashing,
                            suppressHoverAffordances: suppressHoverAffordances
                        ),
                        "hovering: \(isHovering), flashing: \(isFlashing), suppressed: \(suppressHoverAffordances)"
                    )
                }
            }
        }
    }
}

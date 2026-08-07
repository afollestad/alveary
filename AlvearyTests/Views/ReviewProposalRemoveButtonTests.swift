import AppKit
import XCTest

@testable import Alveary

/// Removing a staged comment has no undo, so the control takes two presses. These pin that shape —
/// a single press must never reach the coordinator.
@MainActor
final class ReviewProposalRemoveButtonTests: XCTestCase {
    func testTheFirstPressArmsInsteadOfRemoving() {
        var confirmations = 0
        let button = makeButton { confirmations += 1 }

        _ = button.accessibilityPerformPress()

        XCTAssertEqual(confirmations, 0)
        XCTAssertEqual(button.accessibilityLabel(), "Confirm removing this proposed comment")
    }

    func testTheSecondPressRemovesAndDisarms() {
        var confirmations = 0
        let button = makeButton { confirmations += 1 }

        _ = button.accessibilityPerformPress()
        _ = button.accessibilityPerformPress()

        XCTAssertEqual(confirmations, 1)
        // Disarmed before the callback, so a card that survives the removal is not left armed.
        XCTAssertEqual(button.accessibilityLabel(), "Remove proposed comment")
    }

    /// The card views are pooled, so a reconfigure means this button now stands for a different
    /// comment; an armed pill carried across would remove the wrong one on its next press.
    func testReconfiguringDisarms() {
        var confirmations = 0
        let button = makeButton { confirmations += 1 }
        _ = button.accessibilityPerformPress()

        button.configure(fontSize: 11)
        _ = button.accessibilityPerformPress()

        XCTAssertEqual(confirmations, 0)
    }

    /// The pill widens to hold `Confirm` and shrinks back, but only its frame moves — the alignment
    /// rect's height is what the author row lays out by, so the row never changes height.
    func testArmingWidensTheControlWithoutChangingItsHeight() {
        let button = makeButton {}
        let idleWidth = button.intrinsicContentSize.width

        _ = button.accessibilityPerformPress()

        XCTAssertGreaterThan(button.intrinsicContentSize.width, idleWidth)
        XCTAssertEqual(
            button.intrinsicContentSize.height,
            AppKitReviewProposalCommentRemoveButton.alignmentDiameter
        )
    }

    private func makeButton(onConfirm: @escaping () -> Void) -> AppKitReviewProposalCommentRemoveButton {
        let button = AppKitReviewProposalCommentRemoveButton()
        button.configure(fontSize: 11)
        button.onConfirm = onConfirm
        return button
    }
}

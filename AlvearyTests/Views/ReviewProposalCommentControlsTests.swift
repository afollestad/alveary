import AppKit
import XCTest

@testable import Alveary

/// The two trailing controls on a staged comment's card. Both are deliberately the pane's own
/// controls rebuilt in AppKit, so these pin the parts that would otherwise drift apart.
@MainActor
final class ReviewProposalCommentControlsTests: XCTestCase {
    /// One press, no arming step: the pane does not confirm deleting an unpublished comment
    /// either, because nothing is published.
    func testTheMenusDeleteRowRemovesInOneInvocation() throws {
        var deletions = 0
        let button = AppKitReviewProposalCommentMenuButton()
        button.configure(fontSize: 11)
        button.onDelete = { deletions += 1 }

        let item = try XCTUnwrap(button.makeMenu().items.first)
        _ = item.target?.perform(item.action, with: item)

        XCTAssertEqual(deletions, 1)
    }

    /// A staged comment cannot be edited in place — remove and re-add — so Delete is the whole
    /// menu, and it is worded the way the pane words it.
    func testTheMenuOffersOnlyThePanesDeleteRow() {
        let button = AppKitReviewProposalCommentMenuButton()

        let titles = button.makeMenu().items.map(\.title)

        XCTAssertEqual(titles, [PullRequestCommentActionsMenu.deleteTitle])
    }

    func testTheMenuTakesThePanesHitTargetAndName() {
        let button = AppKitReviewProposalCommentMenuButton()

        XCTAssertEqual(button.intrinsicContentSize, PullRequestCommentActionsMenu.hitTargetSize)
        XCTAssertEqual(button.accessibilityLabel(), PullRequestCommentActionsMenu.name)
    }

    /// Single press, unlike the menu beside it: jumping navigates rather than destroys.
    func testJumpingTakesOnePress() {
        var jumps = 0
        let button = AppKitReviewProposalCommentJumpButton()
        button.configure(fontSize: 11)
        button.onJump = { jumps += 1 }

        _ = button.accessibilityPerformPress()

        XCTAssertEqual(jumps, 1)
    }

    /// The visible label is abbreviated to fit the author row; the name a screen reader and the
    /// tooltip carry is not.
    func testJumpingIsNamedInFullEvenThoughItsLabelIsAbbreviated() {
        let button = AppKitReviewProposalCommentJumpButton()
        button.configure(fontSize: 11)

        XCTAssertEqual(button.accessibilityLabel(), PullRequestCommentRevealAction.transcriptName)
        XCTAssertEqual(button.toolTip, PullRequestCommentRevealAction.transcriptName)
    }

    /// Hover is the pane's own brightening, and it has to run off the shared ramp rather than a
    /// number of this file's own — the two are one affordance, so a drift here is visible only by
    /// putting the transcript beside the pane. Contrast is pinned rather than read from the host,
    /// or a runner with Increase Contrast on would assert 1 against 1 and prove nothing.
    func testJumpingBrightensOnHoverThroughThePanesRamp() {
        let button = AppKitReviewProposalCommentJumpButton()
        button.configure(fontSize: 11)
        button.increasesContrast = { false }

        let resting = InlineActionButtonOpacity.resting(increasesContrast: false)
        XCTAssertLessThan(resting, InlineActionButtonOpacity.active)
        XCTAssertEqual(button.alphaValue, resting, accuracy: 0.0001)

        button.mouseEntered(with: Self.hoverEvent)
        XCTAssertEqual(button.alphaValue, InlineActionButtonOpacity.active, accuracy: 0.0001)

        button.mouseExited(with: Self.hoverEvent)
        XCTAssertEqual(button.alphaValue, resting, accuracy: 0.0001)
    }

    /// Increase Contrast drops the resting fade entirely, so the label keeps the contrast it had
    /// before this style existed and hovering becomes a no-op rather than a legibility cliff.
    func testIncreasedContrastKeepsTheLabelAtFullStrength() {
        let button = AppKitReviewProposalCommentJumpButton()
        button.configure(fontSize: 11)
        button.increasesContrast = { true }

        XCTAssertEqual(button.alphaValue, InlineActionButtonOpacity.active, accuracy: 0.0001)

        button.mouseEntered(with: Self.hoverEvent)

        XCTAssertEqual(button.alphaValue, InlineActionButtonOpacity.active, accuracy: 0.0001)
    }

    /// Brightening is the *text* control's cue only. The menu beside it is an icon control and
    /// draws its own fill in `draw(_:)`, so a change that reached for `alphaValue` on the shared
    /// base class would give it a second, wrong cue.
    func testTheMenuDoesNotBrightenOnHover() {
        let button = AppKitReviewProposalCommentMenuButton()
        button.configure(fontSize: 11)

        button.mouseEntered(with: Self.hoverEvent)

        XCTAssertEqual(button.alphaValue, 1, accuracy: 0.0001)
    }

    /// Icon plus label, so the control has to be wider than the glyph box the pane pairs with
    /// caption text — a regression here would mean the title stopped being laid out.
    func testJumpingRendersItsLabelBesideTheGlyph() {
        let button = AppKitReviewProposalCommentJumpButton()
        button.configure(fontSize: 11)

        XCTAssertGreaterThan(button.fittingSize.width, ActionButtonMetrics.inlineOcticonGlyphSize * 2)
    }

    /// `mouseEntered`/`mouseExited` read nothing off the event, and `NSEvent.mouseEvent` rejects the
    /// tracking-area types outright, so one `.mouseMoved` stand-in serves every case.
    private static var hoverEvent: NSEvent {
        NSEvent.mouseEvent(
            with: .mouseMoved,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        ) ?? NSEvent()
    }
}

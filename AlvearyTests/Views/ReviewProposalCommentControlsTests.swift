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

    /// Icon plus label, so the control has to be wider than the glyph box the pane pairs with
    /// caption text — a regression here would mean the title stopped being laid out.
    func testJumpingRendersItsLabelBesideTheGlyph() {
        let button = AppKitReviewProposalCommentJumpButton()
        button.configure(fontSize: 11)

        XCTAssertGreaterThan(button.fittingSize.width, ActionButtonMetrics.inlineOcticonGlyphSize * 2)
    }
}

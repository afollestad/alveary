import XCTest

@testable import Alveary

/// The review footer's split-button options and the fallback that keeps the button
/// rendered when the stored kind no longer names one.
final class PullRequestReviewFooterActionTests: XCTestCase {
    func testSubmitReviewLeadsSoAFooterWithNoStoredPickOpensTheComposer() {
        XCTAssertEqual(PullRequestReviewFooterAction.all.map(\.kind), [.submitReview, .agenticReview])
    }

    func testEveryKindHasItsOwnTitleAndGlyph() {
        let submit = PullRequestReviewFooterAction.action(for: .submitReview)
        let agentic = PullRequestReviewFooterAction.action(for: .agenticReview)

        XCTAssertEqual(submit.title, "Submit review...")
        XCTAssertEqual(submit.icon, .octicon("CodeReviewOcticon16"))
        XCTAssertEqual(agentic.title, "Agentic review")
        // The same glyph the Agents settings page uses for "an agent does this".
        XCTAssertEqual(agentic.icon, .system("brain"))
    }

    func testAStoredKindRoundTripsThroughItsRawValue() {
        XCTAssertEqual(PullRequestReviewFooterAction.kind(fromStored: "agenticReview"), .agenticReview)
        XCTAssertEqual(PullRequestReviewFooterAction.kind(fromStored: "submitReview"), .submitReview)
    }

    /// A kind written by a newer build, or none at all, must still leave a usable button.
    func testAnUnknownOrAbsentStoredKindFallsBackToSubmitReview() {
        XCTAssertEqual(PullRequestReviewFooterAction.kind(fromStored: nil), .submitReview)
        XCTAssertEqual(PullRequestReviewFooterAction.kind(fromStored: ""), .submitReview)
        XCTAssertEqual(PullRequestReviewFooterAction.kind(fromStored: "someFutureKind"), .submitReview)
    }
}

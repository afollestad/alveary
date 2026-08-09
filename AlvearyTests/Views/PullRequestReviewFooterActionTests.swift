import XCTest

@testable import Alveary

/// The review footer's split-button options, the authorship that picks which one leads, and the
/// fallback that keeps the button rendered when the stored kind no longer names one.
final class PullRequestReviewFooterActionTests: XCTestCase {
    func testTheMenuReadsThroughThePullRequestsLife() {
        XCTAssertEqual(
            PullRequestReviewFooterAction.all.map(\.kind),
            [.submitReview, .agenticReview, .addressFeedback]
        )
    }

    func testEveryKindHasItsOwnTitleAndGlyph() {
        let submit = PullRequestReviewFooterAction.action(for: .submitReview)
        let agentic = PullRequestReviewFooterAction.action(for: .agenticReview)
        let feedback = PullRequestReviewFooterAction.action(for: .addressFeedback)

        XCTAssertEqual(submit.title, "Submit review...")
        XCTAssertEqual(submit.icon, .octicon(.codeReview16))
        XCTAssertEqual(agentic.title, "Agentic review")
        XCTAssertEqual(feedback.title, "Address feedback")
        // Both agentic options wear the glyph the Agents settings page uses for
        // "an agent does this".
        XCTAssertEqual(agentic.icon, .system("brain"))
        XCTAssertEqual(feedback.icon, .system("brain"))
    }

    func testAStoredKindRoundTripsThroughItsRawValue() {
        XCTAssertEqual(
            PullRequestReviewFooterAction.kind(fromStored: "addressFeedback", default: .submitReview),
            .addressFeedback
        )
        XCTAssertEqual(
            PullRequestReviewFooterAction.kind(fromStored: "agenticReview", default: .submitReview),
            .agenticReview
        )
        XCTAssertEqual(
            PullRequestReviewFooterAction.kind(fromStored: "submitReview", default: .addressFeedback),
            .submitReview
        )
    }

    /// A kind written by a newer build, or none at all, must still leave a usable button — and
    /// which one is right depends on whose pull request it is, so the caller supplies it.
    func testAnUnknownOrAbsentStoredKindFallsBackToTheCallersDefault() {
        XCTAssertEqual(PullRequestReviewFooterAction.kind(fromStored: nil, default: .addressFeedback), .addressFeedback)
        XCTAssertEqual(PullRequestReviewFooterAction.kind(fromStored: "", default: .agenticReview), .agenticReview)
        XCTAssertEqual(
            PullRequestReviewFooterAction.kind(fromStored: "someFutureKind", default: .submitReview),
            .submitReview
        )
    }

    // MARK: - Authorship

    /// The list row's `isAuthored` settles before any detail does, so it decides on its own.
    func testAnAuthoredRowIsYoursBeforeTheDetailLands() {
        let summary = makePullRequestSummary(number: 7, isAuthored: true)

        XCTAssertEqual(PullRequestReviewFooterAuthorship.resolve(summary: summary, detail: nil), .authored)
    }

    /// The detail's viewer is the confirmation for a row the involvement search did not mark.
    func testTheDetailsViewerDecidesWhenTheRowDidNot() {
        let summary = makePullRequestSummary(number: 7, author: "alice")
        var mine = makePullRequestDetail(id: summary.id)
        mine.viewerLogin = "alice"
        var theirs = makePullRequestDetail(id: summary.id)
        theirs.viewerLogin = "bob"

        XCTAssertEqual(PullRequestReviewFooterAuthorship.resolve(summary: summary, detail: mine), .authored)
        XCTAssertEqual(PullRequestReviewFooterAuthorship.resolve(summary: summary, detail: theirs), .other)
    }

    /// A detail with no viewer proves nothing, so the unmarked row stands.
    func testARowWithNoViewerToCompareAgainstIsSomebodyElses() {
        let summary = makePullRequestSummary(number: 7)

        XCTAssertEqual(PullRequestReviewFooterAuthorship.resolve(summary: summary, detail: nil), .other)
        XCTAssertEqual(
            PullRequestReviewFooterAuthorship.resolve(summary: summary, detail: makePullRequestDetail(id: summary.id)),
            .other
        )
    }

    /// An identifier-opened pane has no row at all until `loadDetail` backfills one.
    func testAPaneWithNoRowKnowsNothingYet() {
        XCTAssertEqual(PullRequestReviewFooterAuthorship.resolve(summary: nil, detail: nil), .unknown)
    }

    /// GitHub rejects Approve and Request changes on your own pull request; `.unknown` withholds
    /// them too, because offering one GitHub would reject is worse than withholding one it would
    /// accept.
    func testOnlySomebodyElsesPullRequestTakesAVerdict() {
        XCTAssertTrue(PullRequestReviewFooterAuthorship.other.allowsVerdictEvents)
        XCTAssertFalse(PullRequestReviewFooterAuthorship.authored.allowsVerdictEvents)
        XCTAssertFalse(PullRequestReviewFooterAuthorship.unknown.allowsVerdictEvents)
    }

    func testYourOwnPullRequestOpensOnAddressingItsFeedback() {
        XCTAssertEqual(PullRequestReviewFooterAuthorship.authored.defaultFooterActionKind, .addressFeedback)
        XCTAssertEqual(PullRequestReviewFooterAuthorship.other.defaultFooterActionKind, .agenticReview)
        XCTAssertEqual(PullRequestReviewFooterAuthorship.unknown.defaultFooterActionKind, .agenticReview)
    }
}

import SwiftData
import XCTest

@testable import Alveary

/// Submitting a review from the pane while a proposal is pending: one GitHub review carries the
/// staged comments and the viewer's own draft, under the verdict and summary the proposal supplies
/// when the footer supplies neither.
///
/// Split from `PullRequestsViewModelTests+ReviewProposalAttachment.swift`, which owns resolving a
/// proposal into the pane and composing into it, and which holds the shared
/// `ReviewProposalAttachmentFixture`.
@MainActor
extension PullRequestsViewModelTests {
    /// Both sets are one GitHub review: the staged comments are written into the same draft the
    /// viewer's own pending comments live in, and that draft is published once.
    func testSubmittingPublishesTheStagedCommentsAndResolvesTheProposal() async throws {
        let fixture = try ReviewProposalAttachmentFixture()
        await fixture.openPane()
        fixture.viewModel.updateOverallReviewComment("Looks fine.")

        let didSubmit = await fixture.viewModel.submitReview(event: .comment)

        XCTAssertTrue(didSubmit)
        XCTAssertEqual(fixture.service.addedPendingComments.map(\.body), ["Staged remark"])
        // The footer's own summary outranks the proposal's body.
        XCTAssertEqual(fixture.service.submittedPendingReviews.map(\.body), ["Looks fine."])
        XCTAssertTrue(fixture.service.submittedReviews.isEmpty)
        // Confirming clears the envelope, so the proposal drops out with no detaching to do.
        XCTAssertNil(fixture.viewModel.activePendingReviewProposal)
        XCTAssertEqual(fixture.session?.pendingReview.overallComment, "")
        XCTAssertFalse(try XCTUnwrap(fixture.session?.pendingReview.isSubmitting))
    }

    /// The footer's picker used to start at Comment and never read the proposal, so an untouched
    /// pane published a COMMENT review over whatever the model proposed and the card displayed.
    func testAnUntouchedPaneSubmitsTheProposedVerdictRatherThanComment() async throws {
        let fixture = try ReviewProposalAttachmentFixture(proposalEvent: "request_changes")
        await fixture.openPane()

        XCTAssertEqual(
            fixture.viewModel.activePendingReviewProposal?.proposedEvent,
            .requestChanges
        )
        XCTAssertEqual(
            fixture.coordinator.selectedEvent(forProposalID: ReviewProposalAttachmentFixture.proposalID),
            .requestChanges
        )

        let didSubmit = await fixture.viewModel.submitReview(event: .requestChanges)

        XCTAssertTrue(didSubmit)
        XCTAssertEqual(fixture.service.submittedPendingReviews.map(\.event), [.requestChanges])
        // Nothing was typed, so the model's body is what publishes.
        XCTAssertEqual(fixture.service.submittedPendingReviews.map(\.body), ["Some notes."])
    }

    /// GitHub refuses a request-changes review with no body, so the guard demands one — and used
    /// to read only the composer, which a seeded verdict arrives with empty. Submit disabled itself
    /// over a body `confirm` was about to supply from the proposal.
    func testARequestChangesProposalSubmitsWithTheComposerUntouched() async throws {
        let fixture = try ReviewProposalAttachmentFixture(proposalEvent: "request_changes")
        await fixture.openPane()

        XCTAssertEqual(fixture.session?.pendingReview.overallComment, "")

        let didSubmit = await fixture.viewModel.submitReview(event: .requestChanges)

        XCTAssertTrue(didSubmit)
    }

    /// What the footer's picker binds to. The proposal owns the verdict, so the pane reads back
    /// what the model proposed rather than the footer's own `comment` default.
    func testThePanesVerdictStartsAtWhatTheModelProposed() async throws {
        let fixture = try ReviewProposalAttachmentFixture(proposalEvent: "request_changes")
        await fixture.openPane()

        XCTAssertEqual(fixture.viewModel.selectedReviewEvent(for: fixture.target), .requestChanges)
    }

    /// No proposal means no owner, and the footer keeps its own selection — nil is that signal.
    func testThePanesVerdictIsUnownedWithNoProposalPending() async throws {
        let fixture = try ReviewProposalAttachmentFixture(proposalNumber: 999)
        await fixture.openPane()

        XCTAssertNil(fixture.viewModel.selectedReviewEvent(for: fixture.target))
        XCTAssertFalse(fixture.viewModel.selectReviewEvent(.approve, for: fixture.target))
    }

    /// The picker is one value with two editors while a proposal is pending, so a verdict picked
    /// on the transcript card is the one the pane reads, and vice versa.
    func testTheCardAndThePaneEditOneVerdict() async throws {
        let fixture = try ReviewProposalAttachmentFixture(proposalEvent: "request_changes")
        await fixture.openPane()

        // The card's picker.
        fixture.coordinator.selectEvent(.approve, forProposalID: ReviewProposalAttachmentFixture.proposalID)
        XCTAssertEqual(fixture.viewModel.selectedReviewEvent(for: fixture.target), .approve)

        // The pane's picker.
        XCTAssertTrue(fixture.viewModel.selectReviewEvent(.comment, for: fixture.target))
        XCTAssertEqual(
            fixture.coordinator.selectedEvent(forProposalID: ReviewProposalAttachmentFixture.proposalID),
            .comment
        )

        let didSubmit = await fixture.viewModel.submitReview(
            event: try XCTUnwrap(fixture.viewModel.selectedReviewEvent(for: fixture.target))
        )

        XCTAssertTrue(didSubmit)
        XCTAssertEqual(fixture.service.submittedPendingReviews.map(\.event), [.comment])
    }

    /// `confirm`'s precedence, which both submit gates now read rather than re-deriving.
    func testTheResolvedSummaryPrefersTheTypedTextAndFallsBackToTheProposal() async throws {
        let fixture = try ReviewProposalAttachmentFixture()
        await fixture.openPane()
        let session = try XCTUnwrap(fixture.session)

        XCTAssertEqual(
            fixture.viewModel.resolvedReviewSummary(for: fixture.target, session: session),
            "Some notes."
        )

        fixture.viewModel.updateOverallReviewComment("Mine.")
        let typed = try XCTUnwrap(fixture.session)
        XCTAssertEqual(
            fixture.viewModel.resolvedReviewSummary(for: fixture.target, session: typed),
            "Mine."
        )
        // A live editor the user emptied outranks whatever is still serialized behind it.
        XCTAssertEqual(
            fixture.viewModel.resolvedReviewSummary(for: fixture.target, session: typed, typedOverride: ""),
            "Some notes."
        )
    }

    func testAFailedProposalSubmitLeavesTheReviewRetryable() async throws {
        let fixture = try ReviewProposalAttachmentFixture()
        await fixture.openPane()
        fixture.service.detailResult = .failure(.rateLimited)

        let didSubmit = await fixture.viewModel.submitReview(event: .comment)

        XCTAssertFalse(didSubmit)
        XCTAssertNotNil(fixture.session?.pendingReview.submissionError)
        XCTAssertFalse(try XCTUnwrap(fixture.session?.pendingReview.isSubmitting))
        // Unresolved, never wrongly resolved.
        XCTAssertNotNil(fixture.viewModel.activePendingReviewProposal)
    }

    /// The footer's count note, its Submit enablement, and `submitReview`'s own guard all read this
    /// one sum, so the button cannot offer a submit the guard then silently refuses.
    func testTheSubmittableCountCoversStagedComments() async throws {
        let fixture = try ReviewProposalAttachmentFixture()
        await fixture.openPane()
        let session = try XCTUnwrap(fixture.session)
        let onGitHub = try XCTUnwrap(session.detail?.pendingCommentCount)
        let submittable = fixture.viewModel.submittableCommentCount(for: fixture.target, session: session)

        XCTAssertEqual(submittable, onGitHub + 1)
        // A summary-less `.comment` review is submittable *because* of the staged comment.
        XCTAssertTrue(
            PullRequestsViewModel.canSubmitReview(
                event: .comment,
                draft: PendingReviewDraft(),
                pendingCommentCount: submittable
            )
        )
    }
}

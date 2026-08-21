import Foundation
import XCTest

@testable import Alveary

/// `submittingSourceConversationIDs` is the only thing standing between an in-flight submit and the
/// sidebar's working ring — `ConversationWorkActivity` reads nothing else from this coordinator —
/// so every edge of the span owes it an assertion. Its sibling is
/// `ReviewProposalCoordinatorTests+WaitingDot.swift`, which covers the dot underneath.
@MainActor
extension ReviewProposalCoordinatorTests {
    func testSubmittingMarksItsSourceConversationWorking() async throws {
        let fixture = try ReviewProposalFixture()
        let detailGate = PullRequestsServiceGate()
        fixture.service.detailGate = detailGate
        fixture.service.detailResult = .success(
            makePullRequestDetail(id: ReviewProposalFixture.identifier, pendingReviewNodeID: "DRAFT_1")
        )
        let submission = Task {
            await fixture.coordinator.confirm(proposalID: ReviewProposalFixture.proposalID, event: .approve)
        }
        try await fixture.waitForSubmission()

        XCTAssertEqual(fixture.coordinator.submittingSourceConversationIDs, [fixture.conversation.id])
        // The dot stays raised underneath for the same span; the fold is what picks between them.
        XCTAssertEqual(fixture.coordinator.pendingSourceConversationIDs, [fixture.conversation.id])

        detailGate.open()
        let didSubmit = await submission.value

        XCTAssertTrue(didSubmit)
        XCTAssertTrue(fixture.coordinator.submittingSourceConversationIDs.isEmpty)
    }

    /// A failed submit leaves the card confirmable, so the ring has to hand the row back to the dot
    /// rather than to nothing.
    func testAFailedSubmissionDropsTheRingAndKeepsTheDot() async throws {
        let fixture = try ReviewProposalFixture()
        fixture.service.detailResult = .success(
            makePullRequestDetail(id: ReviewProposalFixture.identifier, pendingReviewNodeID: "DRAFT_1")
        )
        fixture.service.submitPendingReviewResult = .failure(.rateLimited)

        let didSubmit = await fixture.coordinator.confirm(
            proposalID: ReviewProposalFixture.proposalID,
            event: .approve
        )

        XCTAssertFalse(didSubmit)
        XCTAssertTrue(fixture.coordinator.submittingSourceConversationIDs.isEmpty)
        XCTAssertEqual(fixture.coordinator.pendingSourceConversationIDs, [fixture.conversation.id])
    }

    /// The reason the span stores its conversation rather than re-deriving it from `presentations`.
    /// Another window rejecting the proposal, an archive clearing the envelope, or a thread delete
    /// all reload this coordinator mid-flight; the ring must outlast that, because the archive guard
    /// reading `PullRequestReviewSubmissionActivity` still refuses the thread.
    ///
    /// `reload()` is called directly rather than through `.pullRequestReviewProposalsChanged`: the
    /// observer is a `Task`, and the point under test is the reload itself, not its delivery.
    func testAReloadMidSubmitKeepsTheRingUp() async throws {
        let fixture = try ReviewProposalFixture()
        let detailGate = PullRequestsServiceGate()
        fixture.service.detailGate = detailGate
        fixture.service.detailResult = .success(
            makePullRequestDetail(id: ReviewProposalFixture.identifier, pendingReviewNodeID: "DRAFT_1")
        )
        let submission = Task {
            await fixture.coordinator.confirm(proposalID: ReviewProposalFixture.proposalID, event: .approve)
        }
        try await fixture.waitForSubmission()

        fixture.conversation.clearPullRequestReviewProposal()
        try fixture.modelContext.save()
        fixture.coordinator.reload()

        XCTAssertTrue(fixture.coordinator.pendingSourceConversationIDs.isEmpty)
        XCTAssertEqual(fixture.coordinator.submittingSourceConversationIDs, [fixture.conversation.id])

        detailGate.open()
        _ = await submission.value

        XCTAssertTrue(fixture.coordinator.submittingSourceConversationIDs.isEmpty)
    }
}

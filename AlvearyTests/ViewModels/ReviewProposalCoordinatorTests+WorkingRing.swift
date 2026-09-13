import Foundation
import XCTest

@testable import Alveary

/// Covers the submitting span consumed by `ConversationWorkActivity`, including reloads while
/// submission is suspended. The base tests assert failure outcomes; the waiting-dot companion
/// covers the pending state underneath this span.
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

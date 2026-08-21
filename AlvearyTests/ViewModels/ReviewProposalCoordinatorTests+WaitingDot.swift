import Foundation
import XCTest

@testable import Alveary

/// `pendingSourceConversationIDs` is the only thing standing between a pending review and the
/// sidebar's blue waiting dot — `ConversationDecisionAttention` reads nothing else from this
/// coordinator — so every path that resolves a proposal owes it an assertion.
///
/// It raises the dot; it does not decide the row shows one. A submit in flight raises the working
/// ring over it — `ReviewProposalCoordinatorTests+WorkingRing.swift`.
@MainActor
extension ReviewProposalCoordinatorTests {
    func testAPendingProposalMarksItsSourceConversationWaiting() throws {
        let fixture = try ReviewProposalFixture()

        XCTAssertEqual(fixture.coordinator.pendingSourceConversationIDs, [fixture.conversation.id])
    }

    func testConfirmingStopsTheSourceConversationWaiting() async throws {
        let fixture = try ReviewProposalFixture()
        fixture.service.detailResult = .success(
            makePullRequestDetail(id: ReviewProposalFixture.identifier, pendingReviewNodeID: "DRAFT_1")
        )

        let didSubmit = await fixture.coordinator.confirm(proposalID: ReviewProposalFixture.proposalID, event: .approve)

        XCTAssertTrue(didSubmit)
        XCTAssertTrue(fixture.coordinator.pendingSourceConversationIDs.isEmpty)
    }

    func testRejectingStopsTheSourceConversationWaiting() throws {
        let fixture = try ReviewProposalFixture()

        XCTAssertTrue(fixture.coordinator.reject(proposalID: ReviewProposalFixture.proposalID))

        XCTAssertTrue(fixture.coordinator.pendingSourceConversationIDs.isEmpty)
    }

    /// The card stays confirmable after a failed submission, so the dot has to stay up with it.
    func testAFailedSubmissionKeepsTheSourceConversationWaiting() async throws {
        let fixture = try ReviewProposalFixture()
        fixture.service.detailResult = .success(
            makePullRequestDetail(id: ReviewProposalFixture.identifier, pendingReviewNodeID: "DRAFT_1")
        )
        fixture.service.submitPendingReviewResult = .failure(.rateLimited)

        let didSubmit = await fixture.coordinator.confirm(proposalID: ReviewProposalFixture.proposalID, event: .approve)

        XCTAssertFalse(didSubmit)
        XCTAssertEqual(fixture.coordinator.pendingSourceConversationIDs, [fixture.conversation.id])
    }
}

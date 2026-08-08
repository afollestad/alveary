import Foundation
import XCTest

@testable import Alveary

/// Editing a review's staged comments before it is submitted. Both surfaces that do it — the
/// transcript card and the pull request pane — rewrite the same envelope and reach nothing.
@MainActor
extension ReviewProposalCoordinatorTests {
    /// Removing a staged comment is a local edit to the envelope, so it rewrites storage and prunes
    /// the already-loaded preview rather than refetching the pull request.
    func testRemovingAStagedCommentRewritesTheEnvelopeAndPrunesThePreview() async throws {
        let fixture = try ReviewProposalFixture(comments: [
            ReviewProposalFixture.stagedComment(path: "File0.swift", line: 1, body: "Guard this."),
            ReviewProposalFixture.stagedComment(path: "File1.swift", line: 1, body: "And this.")
        ])
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier))
        fixture.service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 3))
        fixture.coordinator.ensurePreview(proposalID: ReviewProposalFixture.proposalID)
        try await fixture.waitForPreview()
        let detailCallsBeforeRemoval = fixture.service.detailCallCount

        XCTAssertTrue(fixture.coordinator.removeStagedComment(proposalID: ReviewProposalFixture.proposalID, at: 0))

        XCTAssertEqual(try fixture.conversation.pullRequestReviewProposal()?.stagedComments.map(\.body), ["And this."])
        XCTAssertEqual(fixture.coordinator.presentation(forProposalID: ReviewProposalFixture.proposalID)?.comments.count, 1)
        guard case .loaded(let preview)? = fixture.coordinator.preview(forProposalID: ReviewProposalFixture.proposalID) else {
            return XCTFail("expected a loaded preview")
        }
        XCTAssertEqual(preview.proposedCommentCount, 1)
        XCTAssertEqual(preview.files.map(\.path), ["File1.swift"])
        XCTAssertEqual(preview.annotations.threads.count, 1)
        // No refetch: the click must not cost a detail plus diff round trip.
        XCTAssertEqual(fixture.service.detailCallCount, detailCallsBeforeRemoval)
    }

    /// The envelope's array shifts under a removal, so the surviving cards have to renumber or the
    /// next Remove addresses the wrong comment.
    func testASecondRemovalTargetsTheRenumberedComment() async throws {
        let fixture = try ReviewProposalFixture(comments: [
            ReviewProposalFixture.stagedComment(path: "File0.swift", line: 1, body: "First"),
            ReviewProposalFixture.stagedComment(path: "File1.swift", line: 1, body: "Second"),
            ReviewProposalFixture.stagedComment(path: "File2.swift", line: 1, body: "Third")
        ])
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier))
        fixture.service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 3))
        fixture.coordinator.ensurePreview(proposalID: ReviewProposalFixture.proposalID)
        try await fixture.waitForPreview()

        fixture.coordinator.removeStagedComment(proposalID: ReviewProposalFixture.proposalID, at: 0)
        guard case .loaded(let afterFirst)? = fixture.coordinator.preview(forProposalID: ReviewProposalFixture.proposalID) else {
            return XCTFail("expected a loaded preview")
        }
        // "Third" was index 2 and is now index 1, which is the index its card would send back.
        let renumbered = afterFirst.annotations.threads.values
            .flatMap(\.comments)
            .first { $0.bodyMarkdown == "Third" }
        XCTAssertEqual(renumbered?.proposedIndex, 1)

        fixture.coordinator.removeStagedComment(proposalID: ReviewProposalFixture.proposalID, at: 1)

        XCTAssertEqual(try fixture.conversation.pullRequestReviewProposal()?.stagedComments.map(\.body), ["Second"])
    }

    func testRemovingTheLastStagedCommentLeavesASubmittableSummaryOnlyReview() async throws {
        let fixture = try ReviewProposalFixture(comments: [ReviewProposalFixture.stagedComment(body: "Guard this.")])

        XCTAssertTrue(fixture.coordinator.removeStagedComment(proposalID: ReviewProposalFixture.proposalID, at: 0))

        XCTAssertEqual(fixture.coordinator.presentation(forProposalID: ReviewProposalFixture.proposalID)?.comments, [])
        // The proposal is still pending — removing its comments is not the same as cancelling it.
        XCTAssertNotNil(try fixture.conversation.pullRequestReviewProposal())
        XCTAssertTrue(fixture.coordinator.canSubmit(proposalID: ReviewProposalFixture.proposalID, event: .comment))
    }

    func testConfirmingAfterARemovalPublishesOnlyTheSurvivingComments() async throws {
        let fixture = try ReviewProposalFixture(comments: [
            ReviewProposalFixture.stagedComment(line: 1, body: "First"),
            ReviewProposalFixture.stagedComment(line: 2, body: "Second")
        ])
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier))

        fixture.coordinator.removeStagedComment(proposalID: ReviewProposalFixture.proposalID, at: 0)
        let didSubmit = await fixture.coordinator.confirm(proposalID: ReviewProposalFixture.proposalID, event: .comment)

        XCTAssertTrue(didSubmit)
        XCTAssertEqual(fixture.service.addedPendingComments.map(\.body), ["Second"])
    }

    /// A submission in flight is already publishing the comments it was handed, so the envelope
    /// must not move under it.
    func testRemovingIsRefusedWhileASubmissionIsInFlight() async throws {
        let fixture = try ReviewProposalFixture(comments: [
            ReviewProposalFixture.stagedComment(line: 1, body: "First"),
            ReviewProposalFixture.stagedComment(line: 2, body: "Second")
        ])
        let detailGate = PullRequestsServiceGate()
        fixture.service.detailGate = detailGate
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier))
        let submission = Task { await fixture.coordinator.confirm(proposalID: ReviewProposalFixture.proposalID, event: .comment) }
        try await fixture.waitForSubmission()

        XCTAssertFalse(fixture.coordinator.removeStagedComment(proposalID: ReviewProposalFixture.proposalID, at: 0))

        detailGate.open()
        let didSubmit = await submission.value
        XCTAssertTrue(didSubmit)
        XCTAssertEqual(fixture.service.addedPendingComments.map(\.body), ["First", "Second"])
    }

    func testRemovingNotifiesSoTheCardReRenders() throws {
        let fixture = try ReviewProposalFixture(comments: [ReviewProposalFixture.stagedComment(body: "Guard this.")])
        // Card-only state: the lifecycle notification would also rebuild transcript items, which a
        // removal changes nothing about.
        let notified = XCTNSNotificationExpectation(
            name: .reviewProposalCardStateChanged,
            object: nil,
            notificationCenter: fixture.notificationCenter
        )

        fixture.coordinator.removeStagedComment(proposalID: ReviewProposalFixture.proposalID, at: 0)

        wait(for: [notified], timeout: 1)
    }

    /// The pull request pane composes into the envelope while a proposal is pending, so the
    /// coordinator is not the only writer any more.
    func testAddingAStagedCommentAppendsItToTheEnvelope() async throws {
        let fixture = try ReviewProposalFixture(comments: [ReviewProposalFixture.stagedComment(path: "File0.swift", body: "First")])

        XCTAssertTrue(
            fixture.coordinator.addStagedComment(
                proposalID: ReviewProposalFixture.proposalID,
                path: "File1.swift",
                line: 2,
                side: .left,
                body: "Second"
            )
        )

        let stored = try XCTUnwrap(fixture.conversation.pullRequestReviewProposal()).stagedComments
        // Appended, never inserted: every existing position stays put, so a card's Remove keeps
        // addressing the comment it renders.
        XCTAssertEqual(stored.map(\.body), ["First", "Second"])
        XCTAssertEqual(stored.last?.side, "LEFT")
        XCTAssertEqual(fixture.coordinator.presentation(forProposalID: ReviewProposalFixture.proposalID)?.comments.count, 2)
    }

    /// Removal only ever subtracts, so it can narrow the loaded preview in place; an addition may
    /// need a file the preview deliberately dropped, so it has to reload instead.
    func testAddingAStagedCommentInvalidatesTheCachedPreview() async throws {
        let fixture = try ReviewProposalFixture(comments: [ReviewProposalFixture.stagedComment(path: "File0.swift", body: "First")])
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier))
        fixture.service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 3))
        fixture.coordinator.ensurePreview(proposalID: ReviewProposalFixture.proposalID)
        try await fixture.waitForPreview()

        fixture.coordinator.addStagedComment(
            proposalID: ReviewProposalFixture.proposalID,
            path: "File2.swift",
            line: 1,
            side: .right,
            body: "Second"
        )

        XCTAssertNil(fixture.coordinator.preview(forProposalID: ReviewProposalFixture.proposalID))
        fixture.coordinator.ensurePreview(proposalID: ReviewProposalFixture.proposalID)
        try await fixture.waitForPreview()
        guard case .loaded(let preview)? = fixture.coordinator.preview(forProposalID: ReviewProposalFixture.proposalID) else {
            return XCTFail("expected a reloaded preview")
        }
        XCTAssertEqual(preview.proposedCommentCount, 2)
        XCTAssertEqual(preview.files.map(\.path), ["File0.swift", "File2.swift"])
    }

    /// A submission in flight is already publishing the comments it was handed, so nothing may join
    /// them mid-write.
    func testAddingIsRefusedWhileASubmissionIsInFlight() async throws {
        let fixture = try ReviewProposalFixture(comments: [ReviewProposalFixture.stagedComment(body: "First")])
        let detailGate = PullRequestsServiceGate()
        fixture.service.detailGate = detailGate
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier))
        let submission = Task { await fixture.coordinator.confirm(proposalID: ReviewProposalFixture.proposalID, event: .comment) }
        try await fixture.waitForSubmission()

        XCTAssertFalse(
            fixture.coordinator.addStagedComment(
                proposalID: ReviewProposalFixture.proposalID,
                path: "File0.swift",
                line: 2,
                side: .right,
                body: "Too late"
            )
        )

        detailGate.open()
        let didSubmit = await submission.value
        XCTAssertTrue(didSubmit)
        XCTAssertEqual(fixture.service.addedPendingComments.map(\.body), ["First"])
    }

    /// The envelope is re-read before the edit, so a proposal resolved or superseded since the pane
    /// rendered refuses rather than resurrecting itself under a new comment.
    func testAddingIsRefusedAgainstAVanishedEnvelope() async throws {
        let fixture = try ReviewProposalFixture(comments: [ReviewProposalFixture.stagedComment(body: "First")])
        // Cleared without the change notification, so the coordinator still holds the presentation
        // its callers rendered from — exactly the window the re-read exists to close.
        fixture.conversation.clearPullRequestReviewProposal()
        try fixture.modelContext.save()

        XCTAssertFalse(
            fixture.coordinator.addStagedComment(
                proposalID: ReviewProposalFixture.proposalID,
                path: "File0.swift",
                line: 2,
                side: .right,
                body: "Second"
            )
        )

        XCTAssertNil(try fixture.conversation.pullRequestReviewProposal())
        XCTAssertNotNil(fixture.coordinator.errorMessage(forProposalID: ReviewProposalFixture.proposalID))
    }
}

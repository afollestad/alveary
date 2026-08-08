import Foundation
import XCTest

@testable import Alveary

/// Confirming a review is the one host-tool decision that awaits GitHub, so these cover the
/// ordering that keeps a card from claiming a submission that did not happen.
@MainActor
final class ReviewProposalCoordinatorTests: XCTestCase {
    func testConfirmingSubmitsThePendingDraftAndResolvesTheCard() async throws {
        let fixture = try ReviewProposalFixture()
        fixture.service.detailResult = .success(
            makePullRequestDetail(id: ReviewProposalFixture.identifier, pendingReviewNodeID: "DRAFT_1")
        )

        let didSubmit = await fixture.coordinator.confirm(proposalID: ReviewProposalFixture.proposalID, event: .approve)

        XCTAssertTrue(didSubmit)
        // With a draft on GitHub, submitting finishes *that* review rather than opening a second.
        XCTAssertEqual(
            fixture.service.submittedPendingReviews,
            [.init(reviewNodeID: "DRAFT_1", event: .approve, body: "Looks good to me.")]
        )
        XCTAssertTrue(fixture.service.submittedReviews.isEmpty)
        XCTAssertNil(try fixture.conversation.pullRequestReviewProposal())
        XCTAssertNil(fixture.coordinator.presentation(forProposalID: ReviewProposalFixture.proposalID))
        XCTAssertEqual(fixture.outcomeMarkers().count, 1)
    }

    func testConfirmingWithoutADraftPostsASummaryOnlyReview() async throws {
        let fixture = try ReviewProposalFixture()
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier))
        fixture.service.submitResult = .success(())

        let didSubmit = await fixture.coordinator.confirm(proposalID: ReviewProposalFixture.proposalID, event: .comment)

        XCTAssertTrue(didSubmit)
        XCTAssertEqual(fixture.service.submittedReviews.count, 1)
        XCTAssertTrue(fixture.service.submittedPendingReviews.isEmpty)
    }

    func testTheUserCanSubmitAVerdictOtherThanTheOneProposed() async throws {
        let fixture = try ReviewProposalFixture()
        fixture.service.detailResult = .success(
            makePullRequestDetail(id: ReviewProposalFixture.identifier, pendingReviewNodeID: "DRAFT_1")
        )

        fixture.coordinator.selectEvent(.requestChanges, forProposalID: ReviewProposalFixture.proposalID)
        let selected = fixture.coordinator.selectedEvent(forProposalID: ReviewProposalFixture.proposalID)
        _ = await fixture.coordinator.confirm(proposalID: ReviewProposalFixture.proposalID, event: try XCTUnwrap(selected))

        XCTAssertEqual(fixture.service.submittedPendingReviews.first?.event, .requestChanges)
        // The marker records what was actually submitted, not what the model asked for.
        XCTAssertEqual(
            fixture.outcomeMarkers().first?.content.map { HostToolWidgetOutcomeMarker.title(fromContent: $0) },
            "request_changes"
        )
    }

    func testAFailedSubmissionLeavesTheProposalConfirmableWithItsError() async throws {
        let fixture = try ReviewProposalFixture()
        fixture.service.detailResult = .success(
            makePullRequestDetail(id: ReviewProposalFixture.identifier, pendingReviewNodeID: "DRAFT_1")
        )
        fixture.service.submitPendingReviewResult = .failure(.rateLimited)

        let didSubmit = await fixture.coordinator.confirm(proposalID: ReviewProposalFixture.proposalID, event: .approve)

        XCTAssertFalse(didSubmit)
        // Unresolved, never wrongly resolved: the card must not claim a review was submitted.
        XCTAssertNotNil(try fixture.conversation.pullRequestReviewProposal())
        XCTAssertNotNil(fixture.coordinator.errorMessage(forProposalID: ReviewProposalFixture.proposalID))
        XCTAssertTrue(fixture.outcomeMarkers().isEmpty)
    }

    func testConfirmingWritesStagedCommentsIntoADraftThenSubmitsIt() async throws {
        let fixture = try ReviewProposalFixture(comments: [
            ReviewProposalFixture.stagedComment(line: 1, body: "First"),
            ReviewProposalFixture.stagedComment(line: 2, body: "Second")
        ])
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier))

        let didSubmit = await fixture.coordinator.confirm(proposalID: ReviewProposalFixture.proposalID, event: .comment)

        XCTAssertTrue(didSubmit)
        // No draft existed, so one is opened; the staged comments land in it, in order, and the
        // one publishing call is the submit at the end.
        XCTAssertEqual(fixture.service.createdPendingReviewNodeIDs, ["PR_7"])
        XCTAssertEqual(fixture.service.addedPendingComments.map(\.body), ["First", "Second"])
        XCTAssertEqual(fixture.service.submittedPendingReviews.map(\.reviewNodeID), ["PENDING_REVIEW"])
        XCTAssertTrue(fixture.service.submittedReviews.isEmpty)
        XCTAssertNil(try fixture.conversation.pullRequestReviewProposal())
    }

    func testConfirmingWithAnExistingDraftAdoptsItForTheStagedComments() async throws {
        let fixture = try ReviewProposalFixture(comments: [ReviewProposalFixture.stagedComment(body: "First")])
        fixture.service.detailResult = .success(
            makePullRequestDetail(id: ReviewProposalFixture.identifier, pendingReviewNodeID: "DRAFT_1")
        )

        let didSubmit = await fixture.coordinator.confirm(proposalID: ReviewProposalFixture.proposalID, event: .approve)

        XCTAssertTrue(didSubmit)
        // GitHub allows one pending review per viewer, so the existing draft takes the comments
        // — which is also what keeps publishing the user's own draft comments on confirm.
        XCTAssertTrue(fixture.service.createdPendingReviewNodeIDs.isEmpty)
        XCTAssertEqual(fixture.service.addedPendingComments.map(\.reviewNodeID), ["DRAFT_1"])
        XCTAssertEqual(fixture.service.submittedPendingReviews.map(\.reviewNodeID), ["DRAFT_1"])
    }

    func testAMidWriteFailurePublishesNothingAndLeavesTheCardConfirmable() async throws {
        let fixture = try ReviewProposalFixture(comments: [
            ReviewProposalFixture.stagedComment(line: 1, body: "First"),
            ReviewProposalFixture.stagedComment(line: 2, body: "Second")
        ])
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier))
        fixture.service.addPendingCommentResults = [
            .success(StubPullRequestsService.makePendingThread(path: "File0.swift", line: 1, side: .right, body: "First")),
            .failure(.transport("offline"))
        ]

        let didSubmit = await fixture.coordinator.confirm(proposalID: ReviewProposalFixture.proposalID, event: .comment)

        XCTAssertFalse(didSubmit)
        // The failure struck before the submit, so GitHub holds only a private draft; the card
        // keeps its error and can be confirmed again.
        XCTAssertTrue(fixture.service.submittedPendingReviews.isEmpty)
        XCTAssertNotNil(try fixture.conversation.pullRequestReviewProposal())
        XCTAssertNotNil(fixture.coordinator.errorMessage(forProposalID: ReviewProposalFixture.proposalID))
        XCTAssertTrue(fixture.outcomeMarkers().isEmpty)
    }

    /// The refetched detail carries whatever the first attempt wrote, so a retry writes only what
    /// is missing rather than double-posting the comments that landed.
    func testARetrySkipsStagedCommentsAlreadyInTheDraft() async throws {
        let fixture = try ReviewProposalFixture(comments: [
            ReviewProposalFixture.stagedComment(line: 1, body: "Consider a guard here."),
            ReviewProposalFixture.stagedComment(line: 2, body: "Second")
        ])
        var detail = makePullRequestDetail(id: ReviewProposalFixture.identifier, pendingReviewNodeID: "DRAFT_1")
        detail.reviewThreads = [
            makeReviewThread(nodeID: "THREAD_1", path: "File0.swift", line: 1, isPending: true)
        ]
        fixture.service.detailResult = .success(detail)

        let didSubmit = await fixture.coordinator.confirm(proposalID: ReviewProposalFixture.proposalID, event: .comment)

        XCTAssertTrue(didSubmit)
        XCTAssertEqual(fixture.service.addedPendingComments.map(\.body), ["Second"])
    }

    func testPickingAVerdictNotifiesSoTheCardReRenders() throws {
        let fixture = try ReviewProposalFixture()
        // The transcript re-reads coordinator state only on the change notification, so a
        // silent selection would leave the picker looking stuck on the old verdict.
        let notified = XCTNSNotificationExpectation(
            name: .reviewProposalCardStateChanged,
            object: nil,
            notificationCenter: fixture.notificationCenter
        )

        fixture.coordinator.selectEvent(.comment, forProposalID: ReviewProposalFixture.proposalID)

        wait(for: [notified], timeout: 1)
        XCTAssertEqual(fixture.coordinator.selectedEvent(forProposalID: ReviewProposalFixture.proposalID), .comment)
    }

    func testRejectingClearsTheProposalWithoutTouchingGitHub() async throws {
        let fixture = try ReviewProposalFixture()

        XCTAssertTrue(fixture.coordinator.reject(proposalID: ReviewProposalFixture.proposalID))

        XCTAssertNil(try fixture.conversation.pullRequestReviewProposal())
        XCTAssertEqual(fixture.service.detailCallCount, 0)
        XCTAssertTrue(fixture.service.submittedReviews.isEmpty)
        XCTAssertEqual(fixture.outcomeMarkers().count, 1)
    }

    func testApproveIsUnavailableOnTheViewersOwnPullRequest() async throws {
        let fixture = try ReviewProposalFixture()
        var detail = makePullRequestDetail(id: ReviewProposalFixture.identifier)
        detail.viewerLogin = detail.authorLogin
        detail.reviewThreads = [
            makeReviewThread(nodeID: "THREAD_1", path: "File0.swift", line: 1, isPending: true)
        ]
        fixture.service.detailResult = .success(detail)
        fixture.service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))

        fixture.coordinator.ensurePreview(proposalID: ReviewProposalFixture.proposalID)
        try await fixture.waitForPreview()

        XCTAssertFalse(fixture.coordinator.canSubmit(proposalID: ReviewProposalFixture.proposalID, event: .approve))
        XCTAssertTrue(fixture.coordinator.canSubmit(proposalID: ReviewProposalFixture.proposalID, event: .comment))
    }

    func testThePreviewShowsOnlyTheHunksThePendingCommentsSitOn() async throws {
        let fixture = try ReviewProposalFixture()
        var detail = makePullRequestDetail(id: ReviewProposalFixture.identifier)
        detail.reviewThreads = [
            makeReviewThread(nodeID: "THREAD_1", path: "File1.swift", line: 1, isPending: true),
            // A submitted thread is not part of what confirming would publish.
            makeReviewThread(nodeID: "THREAD_2", path: "File2.swift", line: 1, isPending: false)
        ]
        fixture.service.detailResult = .success(detail)
        fixture.service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 3))

        fixture.coordinator.ensurePreview(proposalID: ReviewProposalFixture.proposalID)
        try await fixture.waitForPreview()

        guard case .loaded(let preview)? = fixture.coordinator.preview(forProposalID: ReviewProposalFixture.proposalID) else {
            return XCTFail("expected a loaded preview")
        }
        XCTAssertEqual(preview.files.map(\.path), ["File1.swift"])
        XCTAssertEqual(preview.pendingCommentCount, 1)
        XCTAssertEqual(preview.annotations.threads.count, 1)
    }

    /// Staged comments exist nowhere on GitHub, so the preview has to render them from the
    /// envelope: attributed to the viewer and marked proposed, on the hunks they anchor to.
    func testThePreviewRendersStagedCommentsWithoutAServerDraft() async throws {
        let fixture = try ReviewProposalFixture(comments: [ReviewProposalFixture.stagedComment(line: 1, body: "Guard this.")])
        var detail = makePullRequestDetail(id: ReviewProposalFixture.identifier)
        detail.viewerLogin = "octocat"
        fixture.service.detailResult = .success(detail)
        fixture.service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 2))

        fixture.coordinator.ensurePreview(proposalID: ReviewProposalFixture.proposalID)
        try await fixture.waitForPreview()

        guard case .loaded(let preview)? = fixture.coordinator.preview(forProposalID: ReviewProposalFixture.proposalID) else {
            return XCTFail("expected a loaded preview")
        }
        XCTAssertEqual(preview.files.map(\.path), ["File0.swift"])
        XCTAssertEqual(preview.proposedCommentCount, 1)
        XCTAssertEqual(preview.pendingCommentCount, 0)
        let thread = try XCTUnwrap(preview.annotations.threads.values.first)
        XCTAssertEqual(thread.comments.first?.author, "octocat")
        XCTAssertEqual(thread.comments.first?.isProposed, true)
    }

    /// The pane footer carries its own summary, which outranks what the model wrote.
    func testConfirmingWithABodyOverrideSubmitsTheOverride() async throws {
        let fixture = try ReviewProposalFixture()
        fixture.service.detailResult = .success(
            makePullRequestDetail(id: ReviewProposalFixture.identifier, pendingReviewNodeID: "DRAFT_1")
        )

        let didSubmit = await fixture.coordinator.confirm(
            proposalID: ReviewProposalFixture.proposalID,
            event: .approve,
            bodyOverride: "The reviewer's own words."
        )

        XCTAssertTrue(didSubmit)
        XCTAssertEqual(fixture.service.submittedPendingReviews.map(\.body), ["The reviewer's own words."])
    }

    func testAFailedPreviewLoadLeavesTheCardConfirmable() async throws {
        let fixture = try ReviewProposalFixture()
        fixture.service.detailResult = .failure(.rateLimited)

        fixture.coordinator.ensurePreview(proposalID: ReviewProposalFixture.proposalID)
        try await fixture.waitForPreview()

        guard case .failed? = fixture.coordinator.preview(forProposalID: ReviewProposalFixture.proposalID) else {
            return XCTFail("expected a failed preview")
        }
        XCTAssertNotNil(fixture.coordinator.presentation(forProposalID: ReviewProposalFixture.proposalID))
    }
}

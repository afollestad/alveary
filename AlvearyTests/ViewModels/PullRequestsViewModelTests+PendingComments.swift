import XCTest

@testable import Alveary

/// Inline comments post to GitHub as pending review comments the moment they
/// are saved, so they survive quitting the app and show up on github.com.
@MainActor
extension PullRequestsViewModelTests {
    func testSavingCommentCreatesPendingReviewAndPostsComment() async {
        let service = StubPullRequestsService()
        let (viewModel, _) = await makeLoadedPullRequestPane(service: service)

        viewModel.openCommentComposer(at: pullRequestReviewAnchor)
        XCTAssertEqual(viewModel.activePaneSession?.composerAnchor, pullRequestReviewAnchor)

        viewModel.updateComposerText("  First draft  ")
        viewModel.saveComposerComment()

        // The comment renders immediately, before GitHub answers, and the
        // composer closes.
        XCTAssertEqual(viewModel.activePaneSession?.detail?.pendingCommentCount, 1)
        XCTAssertNil(viewModel.activePaneSession?.composerAnchor)

        await waitForPullRequestCondition { !service.addedPendingComments.isEmpty }

        XCTAssertEqual(service.createdPendingReviewNodeIDs, ["PR_7"])
        XCTAssertEqual(service.addedPendingComments, [
            StubPullRequestsService.AddedPendingComment(
                reviewNodeID: "PENDING_REVIEW",
                path: pullRequestReviewAnchor.path,
                line: pullRequestReviewAnchor.line,
                side: .right,
                body: "First draft"
            )
        ])
        XCTAssertEqual(viewModel.activePaneSession?.detail?.pendingReviewNodeID, "PENDING_REVIEW")
        // The server copy replaced the placeholder, so the comment now carries
        // the node id its edit and delete actions are addressed by.
        let comment = viewModel.activePaneSession?.detail?.reviewThreads.first?.comments.first
        XCTAssertEqual(comment?.nodeID, "PENDING_COMMENT_First draft")
        XCTAssertEqual(comment?.isPending, true)
    }

    func testSecondCommentReusesTheSamePendingReview() async {
        let service = StubPullRequestsService()
        let (viewModel, _) = await makeLoadedPullRequestPane(service: service)
        // Hold the create open so the second save arrives while it is in flight.
        let gate = PullRequestsServiceGate()
        service.createPendingReviewGate = gate

        viewModel.openCommentComposer(at: pullRequestReviewAnchor)
        viewModel.updateComposerText("First")
        viewModel.saveComposerComment()

        let second = DiffCommentAnchor(path: pullRequestReviewAnchor.path, side: .right, line: 20)
        viewModel.openCommentComposer(at: second)
        viewModel.updateComposerText("Second")
        viewModel.saveComposerComment()

        await waitForPullRequestCondition { service.createdPendingReviewNodeIDs.count == 1 }
        gate.open()
        await waitForPullRequestCondition { service.addedPendingComments.count == 2 }

        // GitHub allows one pending review per viewer; a second create would be
        // rejected and lose a comment.
        XCTAssertEqual(service.createdPendingReviewNodeIDs, ["PR_7"])
        // Both land on that one review. Which of the two waiters resumes first
        // is not defined, and does not matter: each comment has its own anchor.
        XCTAssertEqual(Set(service.addedPendingComments.map(\.body)), ["First", "Second"])
        XCTAssertEqual(service.addedPendingComments.map(\.reviewNodeID), ["PENDING_REVIEW", "PENDING_REVIEW"])
    }

    func testFailedCommentWithdrawsItAndReopensComposer() async {
        let service = StubPullRequestsService()
        let (viewModel, _) = await makeLoadedPullRequestPane(service: service)
        service.addPendingCommentResult = .failure(.requestFailed(statusCode: 422))

        viewModel.openCommentComposer(at: pullRequestReviewAnchor)
        viewModel.updateComposerText("Bad anchor")
        viewModel.saveComposerComment()
        await waitForPullRequestCondition { viewModel.activePaneSession?.composerError != nil }

        XCTAssertEqual(viewModel.activePaneSession?.detail?.pendingCommentCount, 0)
        XCTAssertEqual(viewModel.activePaneSession?.detail?.reviewThreads.count, 0)
        // Nothing typed is lost: the composer reopens where it was, with the text.
        XCTAssertEqual(viewModel.activePaneSession?.composerAnchor, pullRequestReviewAnchor)
        XCTAssertEqual(viewModel.activePaneSession?.composerText, "Bad anchor")
        XCTAssertNotNil(viewModel.activePaneSession?.composerError)
    }

    func testDeletingLastPendingCommentDiscardsTheEmptyReview() async {
        let service = StubPullRequestsService()
        let (viewModel, _) = await makeLoadedPullRequestPane(service: service)

        viewModel.openCommentComposer(at: pullRequestReviewAnchor)
        viewModel.updateComposerText("Remove me")
        viewModel.saveComposerComment()
        await waitForPullRequestCondition { !service.addedPendingComments.isEmpty }

        viewModel.deletePendingComment(nodeID: "PENDING_COMMENT_Remove me")
        XCTAssertEqual(viewModel.activePaneSession?.detail?.reviewThreads.count, 0)
        await waitForPullRequestCondition { !service.deletedPendingReviewNodeIDs.isEmpty }

        XCTAssertEqual(service.deletedPendingCommentNodeIDs, ["PENDING_COMMENT_Remove me"])
        // No empty "pending review" badge is left behind on github.com.
        XCTAssertEqual(service.deletedPendingReviewNodeIDs, ["PENDING_REVIEW"])
        XCTAssertNil(viewModel.activePaneSession?.detail?.pendingReviewNodeID)
    }

    func testFailedPendingDeleteRestoresTheComment() async {
        let service = StubPullRequestsService()
        let (viewModel, _) = await makeLoadedPullRequestPane(service: service)
        service.deletePendingCommentResult = .failure(.requestFailed(statusCode: 500))

        viewModel.openCommentComposer(at: pullRequestReviewAnchor)
        viewModel.updateComposerText("Keep me")
        viewModel.saveComposerComment()
        await waitForPullRequestCondition { !service.addedPendingComments.isEmpty }

        viewModel.deletePendingComment(nodeID: "PENDING_COMMENT_Keep me")
        await waitForPullRequestCondition { viewModel.activePaneSession?.composerError != nil }

        XCTAssertEqual(viewModel.activePaneSession?.detail?.pendingCommentCount, 1)
        XCTAssertEqual(service.deletedPendingReviewNodeIDs, [])
    }

    func testPendingCommentEditSavesOverGraphQL() async {
        let service = StubPullRequestsService()
        let (viewModel, _) = await makeLoadedPullRequestPane(service: service)

        viewModel.openCommentComposer(at: pullRequestReviewAnchor)
        viewModel.updateComposerText("Before")
        viewModel.saveComposerComment()
        await waitForPullRequestCondition { !service.addedPendingComments.isEmpty }

        let pending = DiffLineComment(
            author: "viewer",
            bodyMarkdown: "Before",
            isPending: true,
            remoteID: 9001,
            nodeID: "PENDING_COMMENT_Before",
            canEdit: true,
            canDelete: true
        )
        viewModel.openRemoteCommentEditor(at: pullRequestReviewAnchor, comment: pending)
        // A pending comment edits by node id, never `PATCH pulls/comments/{id}`.
        XCTAssertEqual(viewModel.activePaneSession?.composerPendingCommentNodeID, "PENDING_COMMENT_Before")
        XCTAssertNil(viewModel.activePaneSession?.composerRemoteCommentID)

        viewModel.updateComposerText("After")
        viewModel.saveComposerComment()
        XCTAssertEqual(
            viewModel.activePaneSession?.detail?.reviewThreads.first?.comments.first?.bodyMarkdown,
            "After"
        )
        await waitForPullRequestCondition { !service.updatedPendingComments.isEmpty }

        XCTAssertEqual(service.updatedPendingComments, [
            StubPullRequestsService.UpdatedPendingComment(
                commentNodeID: "PENDING_COMMENT_Before",
                body: "After"
            )
        ])
        XCTAssertEqual(service.updatedComments, [])
    }

    func testSaveComposerIgnoresEmptyDraft() async {
        let service = StubPullRequestsService()
        let (viewModel, _) = await makeLoadedPullRequestPane(service: service)

        viewModel.openCommentComposer(at: pullRequestReviewAnchor)
        viewModel.updateComposerText("   ")
        viewModel.saveComposerComment()

        XCTAssertEqual(service.createdPendingReviewNodeIDs, [])
        XCTAssertEqual(viewModel.activePaneSession?.detail?.pendingCommentCount, 0)
        // The composer stays open so the user can keep typing.
        XCTAssertEqual(viewModel.activePaneSession?.composerAnchor, pullRequestReviewAnchor)
    }
}

// MARK: - Overview timeline routing

@MainActor
extension PullRequestsViewModelTests {
    /// A detail whose one thread holds the viewer's own unsubmitted comment.
    private static func detailWithPendingComment(id: PullRequestIdentifier) -> PullRequestDetail {
        makePullRequestDetail(
            id: id,
            reviewThreads: [
                PullRequestReviewThread(
                    path: "Sources/Parser.swift",
                    line: 12,
                    side: .right,
                    isResolved: false,
                    isOutdated: false,
                    comments: [
                        PullRequestComment(
                            authorLogin: "viewer",
                            authorAvatarURL: nil,
                            bodyMarkdown: "Draft note",
                            createdAt: nil,
                            databaseId: 988,
                            nodeID: "PRRC_pending",
                            viewerCanUpdate: true,
                            viewerCanDelete: true,
                            isPending: true
                        )
                    ],
                    nodeID: "PRT_pending",
                    reviewNodeID: "PRR_pending"
                )
            ],
            pendingReviewNodeID: "PRR_pending"
        )
    }

    /// The Overview's edit entry point must take the GraphQL path for a pending
    /// comment; the REST one would PATCH `pulls/comments/988` and 404 or, worse,
    /// silently edit the wrong resource.
    func testOverviewEditOfPendingCommentUsesGraphQL() async throws {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(Self.detailWithPendingComment(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))

        let comment = try XCTUnwrap(viewModel.activePaneSession?.detail?.reviewThreads.first?.comments.first)
        viewModel.openThreadCommentEditor(comment)

        // No diff anchor: the Overview renders the editor inline in the thread.
        XCTAssertNil(viewModel.activePaneSession?.composerAnchor)
        XCTAssertEqual(viewModel.activePaneSession?.composerPendingCommentNodeID, "PRRC_pending")
        XCTAssertNil(viewModel.activePaneSession?.composerRemoteCommentID)

        viewModel.updateComposerText("Revised note")
        viewModel.saveComposerComment()
        await waitForPullRequestCondition { !service.updatedPendingComments.isEmpty }

        XCTAssertEqual(service.updatedPendingComments.map(\.commentNodeID), ["PRRC_pending"])
        XCTAssertEqual(service.updatedComments, [])
    }

    /// Deleting a pending comment from the Overview skips the confirmation dialog:
    /// nothing is published yet, and the dialog's endpoints are REST-only.
    func testOverviewDeleteOfPendingCommentSkipsConfirmation() async throws {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(Self.detailWithPendingComment(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))

        let comment = try XCTUnwrap(viewModel.activePaneSession?.detail?.reviewThreads.first?.comments.first)
        viewModel.requestDeleteThreadComment(comment)

        XCTAssertNil(viewModel.activePaneSession?.pendingRemoteCommentDeletion)
        XCTAssertEqual(viewModel.activePaneSession?.detail?.reviewThreads.count, 0)
        await waitForPullRequestCondition { !service.deletedPendingCommentNodeIDs.isEmpty }

        XCTAssertEqual(service.deletedPendingCommentNodeIDs, ["PRRC_pending"])
        XCTAssertEqual(service.deletedCommentIDs, [])
        // The now-empty draft review is discarded too.
        await waitForPullRequestCondition { !service.deletedPendingReviewNodeIDs.isEmpty }
        XCTAssertEqual(service.deletedPendingReviewNodeIDs, ["PRR_pending"])
    }
}

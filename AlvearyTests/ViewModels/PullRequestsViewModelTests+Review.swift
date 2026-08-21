import XCTest

@testable import Alveary

@MainActor
extension PullRequestsViewModelTests {
    func testComposerFocusTokenLifecycle() {
        let service = StubPullRequestsService()
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(makePullRequestSummary(number: 7))

        viewModel.openCommentComposer(at: pullRequestReviewAnchor)
        let firstToken = viewModel.activePaneSession?.composerFocusToken
        XCTAssertNotNil(firstToken)

        viewModel.consumeComposerFocusToken()
        XCTAssertNil(viewModel.activePaneSession?.composerFocusToken)

        // Reopening mints a fresh token so the editor re-claims focus.
        viewModel.openCommentComposer(at: pullRequestReviewAnchor)
        XCTAssertNotNil(viewModel.activePaneSession?.composerFocusToken)
        XCTAssertNotEqual(viewModel.activePaneSession?.composerFocusToken, firstToken)
    }

    func testCancelComposerClearsDraftText() {
        let service = StubPullRequestsService()
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(makePullRequestSummary(number: 7))

        viewModel.openCommentComposer(at: pullRequestReviewAnchor)
        viewModel.updateComposerText("Half-written")
        viewModel.cancelCommentComposer()

        XCTAssertNil(viewModel.activePaneSession?.composerAnchor)
        XCTAssertEqual(viewModel.activePaneSession?.composerText, "")
        XCTAssertEqual(service.createdPendingReviewNodeIDs, [])
    }

    func testSubmitValidationMatrix() {
        var draft = PendingReviewDraft()
        func canSubmit(_ event: PullRequestReviewEvent, pendingCommentCount: Int = 0) -> Bool {
            PullRequestsViewModel.canSubmitReview(
                event: event,
                draft: draft,
                pendingCommentCount: pendingCommentCount
            )
        }
        XCTAssertTrue(canSubmit(.approve))
        XCTAssertFalse(canSubmit(.requestChanges))
        XCTAssertFalse(canSubmit(.comment))

        // One pending comment is enough for a plain comment review.
        XCTAssertTrue(canSubmit(.comment, pendingCommentCount: 1))
        XCTAssertFalse(canSubmit(.requestChanges, pendingCommentCount: 1))

        draft.overallComment = "Needs work"
        XCTAssertTrue(canSubmit(.requestChanges))
        XCTAssertTrue(canSubmit(.comment))
    }

    /// With no proposal pending there is nothing to fall back to, so the guard still demands a
    /// summary. `resolvedReviewSummary` widened what counts as one; it must not have widened
    /// *whether* one is required.
    func testSubmitReviewStillRefusesASummarylessRequestChanges() async {
        let service = StubPullRequestsService()
        let (viewModel, _) = await makeLoadedPullRequestPane(service: service)

        let success = await viewModel.submitReview(event: .requestChanges)

        XCTAssertFalse(success)
        XCTAssertTrue(service.submittedPendingReviews.isEmpty)
        XCTAssertTrue(service.submittedReviews.isEmpty)
    }

    func testSubmitReviewFinishesThePendingReviewAndRefetches() async {
        let service = StubPullRequestsService()
        let (viewModel, summary) = await makeLoadedPullRequestPane(service: service)
        service.listResult = .success(PullRequestListResult(summaries: [summary], warnings: []))

        viewModel.openCommentComposer(at: pullRequestReviewAnchor)
        viewModel.updateComposerText("Inline note")
        viewModel.saveComposerComment()
        await waitForPullRequestCondition { !service.addedPendingComments.isEmpty }
        viewModel.updateOverallReviewComment("Please fix")
        let detailCallsBeforeSubmit = service.detailCallCount

        let success = await viewModel.submitReview(event: .requestChanges)

        XCTAssertTrue(success)
        // The existing pending review is finished, not duplicated by a new one.
        XCTAssertEqual(service.submittedPendingReviews, [
            StubPullRequestsService.SubmittedPendingReview(
                reviewNodeID: "PENDING_REVIEW",
                event: .requestChanges,
                body: "Please fix"
            )
        ])
        XCTAssertEqual(service.submittedReviews.count, 0)
        XCTAssertEqual(viewModel.activePaneSession?.pendingReview, PendingReviewDraft())
        XCTAssertEqual(service.detailCallCount, detailCallsBeforeSubmit + 1)
    }

    func testSubmitReviewWithoutPendingReviewPostsSummaryOnly() async {
        let service = StubPullRequestsService()
        let (viewModel, summary) = await makeLoadedPullRequestPane(service: service)
        service.submitResult = .success(())
        service.listResult = .success(PullRequestListResult(summaries: [summary], warnings: []))

        viewModel.updateOverallReviewComment("Looks good")
        let success = await viewModel.submitReview(event: .approve)

        XCTAssertTrue(success)
        XCTAssertEqual(service.submittedPendingReviews, [])
        // Verdict and summary only — there are no inline comments to carry,
        // which is why this endpoint takes none any more.
        XCTAssertEqual(service.submittedReviews, [
            StubPullRequestsService.SubmittedReview(id: summary.id, event: .approve, body: "Looks good")
        ])
    }

    func testSubmitReviewFailureKeepsPendingCommentsAndShowsError() async {
        let service = StubPullRequestsService()
        let (viewModel, _) = await makeLoadedPullRequestPane(service: service)
        service.submitPendingReviewResult = .failure(.requestFailed(statusCode: 422))

        viewModel.openCommentComposer(at: pullRequestReviewAnchor)
        viewModel.updateComposerText("Inline note")
        viewModel.saveComposerComment()
        await waitForPullRequestCondition { !service.addedPendingComments.isEmpty }

        let success = await viewModel.submitReview(event: .comment)

        XCTAssertFalse(success)
        // The comments are already on GitHub, so a failed submit loses nothing.
        XCTAssertEqual(viewModel.activePaneSession?.detail?.pendingCommentCount, 1)
        XCTAssertFalse(viewModel.activePaneSession?.pendingReview.isSubmitting ?? true)
        XCTAssertNotNil(viewModel.activePaneSession?.pendingReview.submissionError)
    }

    /// A detail whose one thread carries an editable/deletable root comment.
    private static func detailWithRemoteComment(
        id: PullRequestIdentifier,
        databaseId: Int,
        body: String
    ) -> PullRequestDetail {
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
                            authorLogin: "afollestad",
                            authorAvatarURL: nil,
                            bodyMarkdown: body,
                            createdAt: nil,
                            databaseId: databaseId,
                            nodeID: "PRRC_root",
                            viewerCanUpdate: true,
                            viewerCanDelete: true
                        )
                    ],
                    nodeID: "PRT_1"
                )
            ]
        )
    }

    func testRemoteCommentEditAppliesOptimisticallyWithoutRefetch() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(
            Self.detailWithRemoteComment(id: summary.id, databaseId: 987, body: "Original body")
        )
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        service.updateCommentResult = .success(())
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))
        let detailCallsBefore = service.detailCallCount

        let remote = DiffLineComment(
            author: "afollestad",
            bodyMarkdown: "Original body",
            isPending: false,
            remoteID: 987,
            canEdit: true,
            canDelete: true
        )
        viewModel.openRemoteCommentEditor(at: pullRequestReviewAnchor, comment: remote)
        XCTAssertEqual(viewModel.activePaneSession?.composerText, "Original body")
        XCTAssertEqual(viewModel.activePaneSession?.composerRemoteCommentID, 987)

        viewModel.updateComposerText("Updated body")
        viewModel.saveComposerComment()

        // The new body renders and the composer closes synchronously.
        XCTAssertEqual(
            viewModel.activePaneSession?.detail?.reviewThreads.first?.comments.first?.bodyMarkdown,
            "Updated body"
        )
        XCTAssertNil(viewModel.activePaneSession?.composerAnchor)
        XCTAssertNil(viewModel.activePaneSession?.composerRemoteCommentID)

        for _ in 0..<2_000 {
            if service.updatedComments.count == 1 {
                break
            }
            await Task.yield()
        }
        XCTAssertEqual(service.updatedComments.first?.commentID, 987)
        XCTAssertEqual(service.updatedComments.first?.body, "Updated body")
        // Optimistic edits never refetch — the local body is already exact.
        XCTAssertEqual(service.detailCallCount, detailCallsBefore)
        // The batch stays untouched — remote edits never join the pending review.
        XCTAssertEqual(viewModel.activePaneSession?.detail?.pendingCommentCount, 0)
    }

    func testRemoteCommentEditFailureRevertsBodyAndReopensComposer() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(
            Self.detailWithRemoteComment(id: summary.id, databaseId: 987, body: "Original body")
        )
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        service.updateCommentResult = .failure(.requestFailed(statusCode: 403))
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))

        let remote = DiffLineComment(
            author: "afollestad",
            bodyMarkdown: "Original body",
            isPending: false,
            remoteID: 987,
            canEdit: true,
            canDelete: true
        )
        viewModel.openRemoteCommentEditor(at: pullRequestReviewAnchor, comment: remote)
        viewModel.updateComposerText("Updated body")
        viewModel.saveComposerComment()
        for _ in 0..<2_000 {
            if viewModel.activePaneSession?.composerError != nil {
                break
            }
            await Task.yield()
        }

        // The optimistic body is undone and the composer reopens with the attempt.
        XCTAssertEqual(
            viewModel.activePaneSession?.detail?.reviewThreads.first?.comments.first?.bodyMarkdown,
            "Original body"
        )
        XCTAssertNotNil(viewModel.activePaneSession?.composerError)
        XCTAssertEqual(viewModel.activePaneSession?.composerRemoteCommentID, 987)
        XCTAssertEqual(viewModel.activePaneSession?.composerText, "Updated body")
    }

    func testRemoteCommentDeletionAppliesOptimisticallyWithoutRefetch() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(
            Self.detailWithRemoteComment(id: summary.id, databaseId: 654, body: "Delete me")
        )
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        service.deleteCommentResult = .success(())
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))
        let detailCallsBefore = service.detailCallCount

        let remote = DiffLineComment(
            author: "afollestad",
            bodyMarkdown: "Delete me",
            isPending: false,
            remoteID: 654,
            canEdit: true,
            canDelete: true
        )
        viewModel.requestDeleteRemoteComment(comment: remote)
        XCTAssertEqual(viewModel.activePaneSession?.pendingRemoteCommentDeletion?.remoteID, 654)

        viewModel.confirmRemoteCommentDeletion()
        // Pending state clears synchronously, before the await.
        XCTAssertNil(viewModel.activePaneSession?.pendingRemoteCommentDeletion)
        for _ in 0..<2_000 {
            if service.deletedCommentIDs == [654] {
                break
            }
            await Task.yield()
        }

        // Deleting the thread's only comment removed the whole thread, no refetch.
        XCTAssertEqual(service.deletedCommentIDs, [654])
        XCTAssertEqual(viewModel.activePaneSession?.detail?.reviewThreads.count, 0)
        XCTAssertEqual(service.detailCallCount, detailCallsBefore)
    }

    func testRemoteCommentDeletionFailureRestoresThread() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(
            Self.detailWithRemoteComment(id: summary.id, databaseId: 654, body: "Delete me")
        )
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        service.deleteCommentResult = .failure(.requestFailed(statusCode: 500))
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))

        let remote = DiffLineComment(
            author: "afollestad",
            bodyMarkdown: "Delete me",
            isPending: false,
            remoteID: 654,
            canEdit: true,
            canDelete: true
        )
        viewModel.requestDeleteRemoteComment(comment: remote)
        viewModel.confirmRemoteCommentDeletion()
        for _ in 0..<2_000 {
            if viewModel.activePaneSession?.composerError != nil {
                break
            }
            await Task.yield()
        }

        // The failed DELETE reinserts the removed thread where it was.
        XCTAssertEqual(viewModel.activePaneSession?.detail?.reviewThreads.count, 1)
        XCTAssertEqual(
            viewModel.activePaneSession?.detail?.reviewThreads.first?.comments.first?.bodyMarkdown,
            "Delete me"
        )
        XCTAssertNotNil(viewModel.activePaneSession?.composerError)
    }

    func testRemoteCommentDeletionCancelKeepsComment() {
        let service = StubPullRequestsService()
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(makePullRequestSummary(number: 7))

        let remote = DiffLineComment(
            author: "afollestad",
            bodyMarkdown: "Keep me",
            isPending: false,
            remoteID: 654,
            canEdit: true,
            canDelete: true
        )
        viewModel.requestDeleteRemoteComment(comment: remote)
        viewModel.cancelRemoteCommentDeletion()

        XCTAssertNil(viewModel.activePaneSession?.pendingRemoteCommentDeletion)
        XCTAssertEqual(service.deletedCommentIDs, [])
    }

    func testRemoteEditorRejectsNonEditableComments() {
        let service = StubPullRequestsService()
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(makePullRequestSummary(number: 7))

        let foreign = DiffLineComment(
            author: "carol",
            bodyMarkdown: "Not yours",
            isPending: false,
            remoteID: 12,
            canEdit: false
        )
        viewModel.openRemoteCommentEditor(at: pullRequestReviewAnchor, comment: foreign)

        XCTAssertNil(viewModel.activePaneSession?.composerAnchor)
        XCTAssertNil(viewModel.activePaneSession?.composerRemoteCommentID)
    }

    func testSubmitReviewRejectedByValidationDoesNotCallService() async {
        let service = StubPullRequestsService()
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(makePullRequestSummary(number: 7))

        let success = await viewModel.submitReview(event: .requestChanges)

        XCTAssertFalse(success)
        XCTAssertEqual(service.submittedReviews.count, 0)
    }
}

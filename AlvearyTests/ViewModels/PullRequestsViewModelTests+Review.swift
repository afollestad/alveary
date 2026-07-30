import XCTest

@testable import Alveary

@MainActor
extension PullRequestsViewModelTests {
    private static let anchor = DiffCommentAnchor(path: "Sources/Parser.swift", side: .right, line: 12)

    func testComposerSaveEditAndRemoveLifecycle() {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)

        viewModel.openCommentComposer(at: Self.anchor)
        XCTAssertEqual(viewModel.activePaneSession?.composerAnchor, Self.anchor)

        viewModel.updateComposerText("  First draft  ")
        viewModel.saveComposerComment()

        let saved = viewModel.activePaneSession?.pendingReview.comments
        XCTAssertEqual(saved?.count, 1)
        XCTAssertEqual(saved?.first?.body, "First draft")
        XCTAssertNil(viewModel.activePaneSession?.composerAnchor)

        // Reopening the composer on the same anchor edits the pending comment in place.
        viewModel.openCommentComposer(at: Self.anchor)
        XCTAssertEqual(viewModel.activePaneSession?.composerText, "First draft")
        viewModel.updateComposerText("Revised")
        viewModel.saveComposerComment()
        XCTAssertEqual(viewModel.activePaneSession?.pendingReview.comments.map(\.body), ["Revised"])

        viewModel.removePendingComment(at: Self.anchor)
        XCTAssertEqual(viewModel.activePaneSession?.pendingReview.comments.count, 0)
    }

    func testSaveComposerIgnoresEmptyDraft() {
        let service = StubPullRequestsService()
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(makePullRequestSummary(number: 7))

        viewModel.openCommentComposer(at: Self.anchor)
        viewModel.updateComposerText("   ")
        viewModel.saveComposerComment()

        XCTAssertEqual(viewModel.activePaneSession?.pendingReview.comments.count, 0)
        // The composer stays open so the user can keep typing.
        XCTAssertEqual(viewModel.activePaneSession?.composerAnchor, Self.anchor)
    }

    func testComposerFocusTokenLifecycle() {
        let service = StubPullRequestsService()
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(makePullRequestSummary(number: 7))

        viewModel.openCommentComposer(at: Self.anchor)
        let firstToken = viewModel.activePaneSession?.composerFocusToken
        XCTAssertNotNil(firstToken)

        viewModel.consumeComposerFocusToken()
        XCTAssertNil(viewModel.activePaneSession?.composerFocusToken)

        // Reopening mints a fresh token so the editor re-claims focus.
        viewModel.openCommentComposer(at: Self.anchor)
        XCTAssertNotNil(viewModel.activePaneSession?.composerFocusToken)
        XCTAssertNotEqual(viewModel.activePaneSession?.composerFocusToken, firstToken)
    }

    func testCancelComposerClearsDraftText() {
        let service = StubPullRequestsService()
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(makePullRequestSummary(number: 7))

        viewModel.openCommentComposer(at: Self.anchor)
        viewModel.updateComposerText("Half-written")
        viewModel.cancelCommentComposer()

        XCTAssertNil(viewModel.activePaneSession?.composerAnchor)
        XCTAssertEqual(viewModel.activePaneSession?.composerText, "")
        XCTAssertEqual(viewModel.activePaneSession?.pendingReview.comments.count, 0)
    }

    func testSubmitValidationMatrix() {
        var draft = PendingReviewDraft()
        XCTAssertTrue(PullRequestsViewModel.canSubmitReview(event: .approve, draft: draft))
        XCTAssertFalse(PullRequestsViewModel.canSubmitReview(event: .requestChanges, draft: draft))
        XCTAssertFalse(PullRequestsViewModel.canSubmitReview(event: .comment, draft: draft))

        draft.comments = [PendingReviewComment(id: UUID(), anchor: Self.anchor, body: "Inline")]
        XCTAssertTrue(PullRequestsViewModel.canSubmitReview(event: .comment, draft: draft))
        XCTAssertFalse(PullRequestsViewModel.canSubmitReview(event: .requestChanges, draft: draft))

        draft.comments = []
        draft.overallComment = "Needs work"
        XCTAssertTrue(PullRequestsViewModel.canSubmitReview(event: .requestChanges, draft: draft))
        XCTAssertTrue(PullRequestsViewModel.canSubmitReview(event: .comment, draft: draft))
    }

    func testSubmitReviewSuccessClearsDraftAndRefetches() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(makePullRequestDetail(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        service.submitResult = .success(())
        service.listResult = .success(PullRequestListResult(summaries: [summary], warnings: []))
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))

        viewModel.openCommentComposer(at: Self.anchor)
        viewModel.updateComposerText("Inline note")
        viewModel.saveComposerComment()
        viewModel.updateOverallReviewComment("Please fix")
        let detailCallsBeforeSubmit = service.detailCallCount

        let success = await viewModel.submitReview(event: .requestChanges)

        XCTAssertTrue(success)
        XCTAssertEqual(service.submittedReviews.count, 1)
        let submitted = service.submittedReviews[0]
        XCTAssertEqual(submitted.id, summary.id)
        XCTAssertEqual(submitted.submission.event, .requestChanges)
        XCTAssertEqual(submitted.submission.body, "Please fix")
        XCTAssertEqual(submitted.submission.comments, [
            PendingReviewSubmission.InlineComment(
                path: Self.anchor.path,
                line: Self.anchor.line,
                side: .right,
                body: "Inline note"
            )
        ])

        XCTAssertEqual(viewModel.activePaneSession?.pendingReview, PendingReviewDraft())
        XCTAssertEqual(service.detailCallCount, detailCallsBeforeSubmit + 1)
    }

    func testSubmitReviewFailureKeepsBatchAndShowsError() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.submitResult = .failure(.requestFailed(statusCode: 422))
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)

        viewModel.openCommentComposer(at: Self.anchor)
        viewModel.updateComposerText("Inline note")
        viewModel.saveComposerComment()

        let success = await viewModel.submitReview(event: .comment)

        XCTAssertFalse(success)
        XCTAssertEqual(viewModel.activePaneSession?.pendingReview.comments.count, 1)
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
        viewModel.openRemoteCommentEditor(at: Self.anchor, comment: remote)
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
        XCTAssertEqual(viewModel.activePaneSession?.pendingReview.comments.count, 0)
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
        viewModel.openRemoteCommentEditor(at: Self.anchor, comment: remote)
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
        viewModel.requestDeleteRemoteComment(at: Self.anchor, comment: remote)
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
        viewModel.requestDeleteRemoteComment(at: Self.anchor, comment: remote)
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
        viewModel.requestDeleteRemoteComment(at: Self.anchor, comment: remote)
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
        viewModel.openRemoteCommentEditor(at: Self.anchor, comment: foreign)

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

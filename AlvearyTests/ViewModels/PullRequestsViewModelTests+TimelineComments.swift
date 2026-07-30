import XCTest

@testable import Alveary

// Overview-timeline comment actions: optimistic issue-comment edit/delete against
// `issues/comments/{id}` and the timeline entry points for review-thread comments.
@MainActor
extension PullRequestsViewModelTests {
    private static func issueComment(
        databaseId: Int? = 321,
        body: String = "Original body",
        canUpdate: Bool = true,
        canDelete: Bool = true
    ) -> PullRequestComment {
        PullRequestComment(
            authorLogin: "carol",
            authorAvatarURL: nil,
            bodyMarkdown: body,
            createdAt: nil,
            databaseId: databaseId,
            nodeID: "IC_321",
            viewerCanUpdate: canUpdate,
            viewerCanDelete: canDelete
        )
    }

    private static func review(
        databaseId: Int? = 555,
        body: String = "Original review body",
        canUpdate: Bool = true
    ) -> PullRequestReview {
        PullRequestReview(
            authorLogin: "carol",
            authorAvatarURL: nil,
            state: .commented,
            bodyMarkdown: body,
            submittedAt: nil,
            databaseId: databaseId,
            nodeID: "PRR_555",
            viewerCanUpdate: canUpdate
        )
    }

    private static func detailWithTimelineThread(id: PullRequestIdentifier) -> PullRequestDetail {
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
                            authorLogin: "carol",
                            authorAvatarURL: nil,
                            bodyMarkdown: "Thread body",
                            createdAt: nil,
                            databaseId: 987,
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

    func testIssueCommentEditAppliesOptimisticallyWithoutRefetch() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(makePullRequestDetail(id: summary.id, comments: [Self.issueComment()]))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        service.updateIssueCommentResult = .success(())
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))
        let detailCallsBefore = service.detailCallCount

        viewModel.openIssueCommentEditor(Self.issueComment())
        XCTAssertEqual(viewModel.activePaneSession?.composerIssueCommentID, 321)
        XCTAssertEqual(viewModel.activePaneSession?.composerText, "Original body")
        XCTAssertNil(viewModel.activePaneSession?.composerAnchor)
        XCTAssertNil(viewModel.activePaneSession?.composerRemoteCommentID)

        viewModel.updateComposerText("Updated body")
        viewModel.saveComposerComment()

        // The new body renders and the inline editor closes synchronously.
        XCTAssertEqual(viewModel.activePaneSession?.detail?.comments.first?.bodyMarkdown, "Updated body")
        XCTAssertNil(viewModel.activePaneSession?.composerIssueCommentID)

        for _ in 0..<2_000 {
            if service.updatedIssueComments.count == 1 {
                break
            }
            await Task.yield()
        }
        XCTAssertEqual(service.updatedIssueComments.first?.commentID, 321)
        XCTAssertEqual(service.updatedIssueComments.first?.body, "Updated body")
        // The review-comment endpoint is never touched, and edits never refetch.
        XCTAssertEqual(service.updatedComments, [])
        XCTAssertEqual(service.detailCallCount, detailCallsBefore)
        XCTAssertEqual(viewModel.activePaneSession?.detail?.pendingCommentCount, 0)
    }

    func testIssueCommentEditFailureRevertsBodyAndReopensEditor() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(makePullRequestDetail(id: summary.id, comments: [Self.issueComment()]))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        service.updateIssueCommentResult = .failure(.requestFailed(statusCode: 403))
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))

        viewModel.openIssueCommentEditor(Self.issueComment())
        viewModel.updateComposerText("Updated body")
        viewModel.saveComposerComment()
        for _ in 0..<2_000 {
            if viewModel.activePaneSession?.composerError != nil {
                break
            }
            await Task.yield()
        }

        // The optimistic body is undone and the editor reopens with the attempt.
        XCTAssertEqual(viewModel.activePaneSession?.detail?.comments.first?.bodyMarkdown, "Original body")
        XCTAssertNotNil(viewModel.activePaneSession?.composerError)
        XCTAssertEqual(viewModel.activePaneSession?.composerIssueCommentID, 321)
        XCTAssertEqual(viewModel.activePaneSession?.composerText, "Updated body")
    }

    func testIssueCommentDeletionAppliesOptimisticallyWithoutRefetch() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(makePullRequestDetail(id: summary.id, comments: [Self.issueComment()]))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        service.deleteIssueCommentResult = .success(())
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))
        let detailCallsBefore = service.detailCallCount

        viewModel.requestDeleteIssueComment(Self.issueComment())
        XCTAssertEqual(
            viewModel.activePaneSession?.pendingRemoteCommentDeletion,
            PendingRemoteCommentDeletion(kind: .issueComment, remoteID: 321)
        )

        viewModel.confirmRemoteCommentDeletion()
        // Pending state clears synchronously, before the await.
        XCTAssertNil(viewModel.activePaneSession?.pendingRemoteCommentDeletion)
        for _ in 0..<2_000 {
            if service.deletedIssueCommentIDs == [321] {
                break
            }
            await Task.yield()
        }

        XCTAssertEqual(service.deletedIssueCommentIDs, [321])
        // The review-comment endpoint is never touched, and no refetch runs.
        XCTAssertEqual(service.deletedCommentIDs, [])
        XCTAssertEqual(viewModel.activePaneSession?.detail?.comments.count, 0)
        XCTAssertEqual(service.detailCallCount, detailCallsBefore)
    }

    func testIssueCommentDeletionFailureRestoresComment() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(makePullRequestDetail(id: summary.id, comments: [Self.issueComment()]))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        service.deleteIssueCommentResult = .failure(.requestFailed(statusCode: 500))
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))

        viewModel.requestDeleteIssueComment(Self.issueComment())
        viewModel.confirmRemoteCommentDeletion()
        for _ in 0..<2_000 {
            if viewModel.activePaneSession?.composerError != nil {
                break
            }
            await Task.yield()
        }

        // The failed DELETE reinserts the comment where it was.
        XCTAssertEqual(viewModel.activePaneSession?.detail?.comments.first?.bodyMarkdown, "Original body")
        XCTAssertNotNil(viewModel.activePaneSession?.composerError)
    }

    func testIssueCommentActionsRejectMissingPermissionsOrID() {
        let service = StubPullRequestsService()
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(makePullRequestSummary(number: 7))

        viewModel.openIssueCommentEditor(Self.issueComment(canUpdate: false))
        XCTAssertNil(viewModel.activePaneSession?.composerIssueCommentID)

        viewModel.openIssueCommentEditor(Self.issueComment(databaseId: nil))
        XCTAssertNil(viewModel.activePaneSession?.composerIssueCommentID)

        viewModel.requestDeleteIssueComment(Self.issueComment(canDelete: false))
        XCTAssertNil(viewModel.activePaneSession?.pendingRemoteCommentDeletion)
    }

    func testReviewBodyEditAppliesOptimisticallyWithoutRefetch() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(makePullRequestDetail(id: summary.id, reviews: [Self.review()]))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        service.updateReviewResult = .success(())
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))
        let detailCallsBefore = service.detailCallCount

        viewModel.openReviewBodyEditor(Self.review())
        XCTAssertEqual(viewModel.activePaneSession?.composerReviewID, 555)
        XCTAssertEqual(viewModel.activePaneSession?.composerText, "Original review body")
        XCTAssertNil(viewModel.activePaneSession?.composerAnchor)
        XCTAssertNil(viewModel.activePaneSession?.composerIssueCommentID)

        viewModel.updateComposerText("Updated review body")
        viewModel.saveComposerComment()

        // The new body renders and the inline editor closes synchronously.
        XCTAssertEqual(viewModel.activePaneSession?.detail?.reviews.first?.bodyMarkdown, "Updated review body")
        XCTAssertNil(viewModel.activePaneSession?.composerReviewID)

        for _ in 0..<2_000 {
            if service.updatedReviews.count == 1 {
                break
            }
            await Task.yield()
        }
        XCTAssertEqual(service.updatedReviews.first?.commentID, 555)
        XCTAssertEqual(service.updatedReviews.first?.body, "Updated review body")
        // The comment endpoints are never touched, and edits never refetch.
        XCTAssertEqual(service.updatedComments, [])
        XCTAssertEqual(service.updatedIssueComments, [])
        XCTAssertEqual(service.detailCallCount, detailCallsBefore)
    }

    func testReviewBodyEditFailureRevertsBodyAndReopensEditor() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(makePullRequestDetail(id: summary.id, reviews: [Self.review()]))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        service.updateReviewResult = .failure(.requestFailed(statusCode: 403))
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))

        viewModel.openReviewBodyEditor(Self.review())
        viewModel.updateComposerText("Updated review body")
        viewModel.saveComposerComment()
        for _ in 0..<2_000 {
            if viewModel.activePaneSession?.composerError != nil {
                break
            }
            await Task.yield()
        }

        // The optimistic body is undone and the editor reopens with the attempt.
        XCTAssertEqual(viewModel.activePaneSession?.detail?.reviews.first?.bodyMarkdown, "Original review body")
        XCTAssertNotNil(viewModel.activePaneSession?.composerError)
        XCTAssertEqual(viewModel.activePaneSession?.composerReviewID, 555)
        XCTAssertEqual(viewModel.activePaneSession?.composerText, "Updated review body")
    }

    func testReviewBodyEditorRejectsMissingPermissionOrID() {
        let service = StubPullRequestsService()
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(makePullRequestSummary(number: 7))

        viewModel.openReviewBodyEditor(Self.review(canUpdate: false))
        XCTAssertNil(viewModel.activePaneSession?.composerReviewID)

        viewModel.openReviewBodyEditor(Self.review(databaseId: nil))
        XCTAssertNil(viewModel.activePaneSession?.composerReviewID)
    }

    func testTimelineThreadCommentEditorSharesTheReviewCommentFlow() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(Self.detailWithTimelineThread(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        service.updateCommentResult = .success(())
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))

        let comment = Self.detailWithTimelineThread(id: summary.id).reviewThreads[0].comments[0]
        viewModel.openThreadCommentEditor(comment)
        // The timeline has no diff anchor; the edit still targets the same
        // review-comment state the Changes tab renders inline.
        XCTAssertNil(viewModel.activePaneSession?.composerAnchor)
        XCTAssertEqual(viewModel.activePaneSession?.composerRemoteCommentID, 987)
        XCTAssertEqual(viewModel.activePaneSession?.composerText, "Thread body")

        viewModel.updateComposerText("Edited from Overview")
        viewModel.saveComposerComment()

        XCTAssertEqual(
            viewModel.activePaneSession?.detail?.reviewThreads.first?.comments.first?.bodyMarkdown,
            "Edited from Overview"
        )
        for _ in 0..<2_000 {
            if service.updatedComments.count == 1 {
                break
            }
            await Task.yield()
        }
        // The PATCH goes to the review-comment endpoint, not issues/comments.
        XCTAssertEqual(service.updatedComments.first?.commentID, 987)
        XCTAssertEqual(service.updatedIssueComments, [])
    }

    func testOverviewThreadReplyInsertsOptimisticallyIntoTheThread() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(Self.detailWithTimelineThread(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        service.replyResult = .success(())
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))

        let thread = Self.detailWithTimelineThread(id: summary.id).reviewThreads[0]
        viewModel.openThreadReplyComposer(thread)
        // No diff anchor: the reply editor renders inline in the Overview thread.
        XCTAssertNil(viewModel.activePaneSession?.composerAnchor)
        XCTAssertEqual(viewModel.activePaneSession?.composerReplyToCommentID, 987)

        viewModel.updateComposerText("Replying from Overview")
        viewModel.saveComposerComment()

        // The placeholder joins the thread synchronously — the nested hierarchy
        // renders straight from `detail.reviewThreads`.
        let comments = viewModel.activePaneSession?.detail?.reviewThreads.first?.comments
        XCTAssertEqual(comments?.count, 2)
        XCTAssertEqual(comments?.last?.bodyMarkdown, "Replying from Overview")
        XCTAssertNil(viewModel.activePaneSession?.composerReplyToCommentID)

        for _ in 0..<2_000 {
            if service.threadReplies.count == 1 {
                break
            }
            await Task.yield()
        }
        XCTAssertEqual(service.threadReplies.first?.commentID, 987)
        XCTAssertEqual(service.threadReplies.first?.body, "Replying from Overview")
    }

    func testOverviewThreadReplyFailureRemovesPlaceholderAndReopensEditor() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(Self.detailWithTimelineThread(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        service.replyResult = .failure(.requestFailed(statusCode: 500))
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))

        let thread = Self.detailWithTimelineThread(id: summary.id).reviewThreads[0]
        viewModel.openThreadReplyComposer(thread)
        viewModel.updateComposerText("Replying from Overview")
        viewModel.saveComposerComment()
        for _ in 0..<2_000 {
            if viewModel.activePaneSession?.composerError != nil {
                break
            }
            await Task.yield()
        }

        // The optimistic placeholder is undone and the inline editor reopens with
        // the attempted text — still anchorless, so it reopens on the Overview.
        XCTAssertEqual(viewModel.activePaneSession?.detail?.reviewThreads.first?.comments.count, 1)
        XCTAssertNil(viewModel.activePaneSession?.composerAnchor)
        XCTAssertEqual(viewModel.activePaneSession?.composerReplyToCommentID, 987)
        XCTAssertEqual(viewModel.activePaneSession?.composerText, "Replying from Overview")
        XCTAssertNotNil(viewModel.activePaneSession?.composerError)
    }

    func testTimelineThreadCommentDeletionUsesReviewEndpoint() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(Self.detailWithTimelineThread(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        service.deleteCommentResult = .success(())
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))

        let comment = Self.detailWithTimelineThread(id: summary.id).reviewThreads[0].comments[0]
        viewModel.requestDeleteThreadComment(comment)
        XCTAssertEqual(
            viewModel.activePaneSession?.pendingRemoteCommentDeletion,
            PendingRemoteCommentDeletion(kind: .reviewComment, remoteID: 987)
        )

        viewModel.confirmRemoteCommentDeletion()
        for _ in 0..<2_000 {
            if service.deletedCommentIDs == [987] {
                break
            }
            await Task.yield()
        }

        XCTAssertEqual(service.deletedCommentIDs, [987])
        XCTAssertEqual(service.deletedIssueCommentIDs, [])
        // Deleting the thread's only comment removed the whole thread.
        XCTAssertEqual(viewModel.activePaneSession?.detail?.reviewThreads.count, 0)
    }
}

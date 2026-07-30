import XCTest

@testable import Alveary

// Optimistic comment actions: reactions, thread replies, and thread resolution.
@MainActor
extension PullRequestsViewModelTests {
    private static let anchor = DiffCommentAnchor(path: "Sources/Parser.swift", side: .right, line: 12)

    private static func reactableComment() -> PullRequestComment {
        PullRequestComment(
            authorLogin: "carol",
            authorAvatarURL: nil,
            bodyMarkdown: "Nice catch",
            createdAt: nil,
            databaseId: 654,
            nodeID: "PRRC_654",
            reactions: [PullRequestCommentReaction(content: .thumbsUp, count: 2, viewerHasReacted: true)]
        )
    }

    func testToggleReactionAppliesOptimisticallyWithoutRefetch() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(makePullRequestDetail(id: summary.id, comments: [Self.reactableComment()]))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))
        let detailCallsBefore = service.detailCallCount

        // The viewer has not reacted with EYES yet, so the toggle adds — instantly.
        viewModel.toggleReaction(subjectID: "PRRC_654", content: "EYES", viewerHasReacted: false)
        XCTAssertEqual(viewModel.activePaneSession?.detail?.comments.first?.reactions, [
            PullRequestCommentReaction(content: .thumbsUp, count: 2, viewerHasReacted: true),
            PullRequestCommentReaction(content: .eyes, count: 1, viewerHasReacted: true)
        ])
        // The two toggles run in independent tasks; wait so the recording order is fixed.
        for _ in 0..<2_000 {
            if service.reactionMutations.count == 1 {
                break
            }
            await Task.yield()
        }

        // Removing an existing reaction drops its count immediately too.
        viewModel.toggleReaction(subjectID: "PRRC_654", content: "THUMBS_UP", viewerHasReacted: true)
        XCTAssertEqual(viewModel.activePaneSession?.detail?.comments.first?.reactions, [
            PullRequestCommentReaction(content: .thumbsUp, count: 1, viewerHasReacted: false),
            PullRequestCommentReaction(content: .eyes, count: 1, viewerHasReacted: true)
        ])

        for _ in 0..<2_000 {
            if service.reactionMutations.count == 2 {
                break
            }
            await Task.yield()
        }
        XCTAssertEqual(service.reactionMutations, [
            StubPullRequestsService.ReactionMutation(subjectID: "PRRC_654", content: .eyes, isAdd: true),
            StubPullRequestsService.ReactionMutation(subjectID: "PRRC_654", content: .thumbsUp, isAdd: false)
        ])
        // Optimistic reactions never refetch the detail.
        XCTAssertEqual(service.detailCallCount, detailCallsBefore)
    }

    func testToggleReactionRevertsWhenMutationFails() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(makePullRequestDetail(id: summary.id, comments: [Self.reactableComment()]))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        service.reactionResult = .failure(.requestFailed(statusCode: 502))
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))

        viewModel.toggleReaction(subjectID: "PRRC_654", content: "EYES", viewerHasReacted: false)
        for _ in 0..<2_000 {
            if viewModel.activePaneSession?.composerError != nil {
                break
            }
            await Task.yield()
        }

        // The failed add is undone and the error surfaces on the comment banner.
        XCTAssertEqual(viewModel.activePaneSession?.detail?.comments.first?.reactions, [
            PullRequestCommentReaction(content: .thumbsUp, count: 2, viewerHasReacted: true)
        ])
        XCTAssertNotNil(viewModel.activePaneSession?.composerError)
    }

    private static func detailWithThread(id: PullRequestIdentifier) -> PullRequestDetail {
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
                            bodyMarkdown: "Root",
                            createdAt: nil,
                            databaseId: 987,
                            nodeID: "PRRC_root"
                        )
                    ],
                    nodeID: "PRT_1"
                )
            ]
        )
    }

    func testThreadReplyAppliesOptimisticallyThenReconciles() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(Self.detailWithThread(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))
        let detailCallsBefore = service.detailCallCount

        let thread = DiffLineCommentThread(
            comments: [
                DiffLineComment(author: "carol", bodyMarkdown: "Root", isPending: false, remoteID: 987)
            ],
            threadID: "PRT_1"
        )
        viewModel.openThreadReplyComposer(at: Self.anchor, thread: thread)
        XCTAssertEqual(viewModel.activePaneSession?.composerReplyToCommentID, 987)

        viewModel.updateComposerText("  On it.  ")
        viewModel.saveComposerComment()

        // The placeholder joins the thread and the composer closes synchronously.
        XCTAssertEqual(viewModel.activePaneSession?.detail?.reviewThreads.first?.comments.count, 2)
        XCTAssertEqual(
            viewModel.activePaneSession?.detail?.reviewThreads.first?.comments.last?.bodyMarkdown,
            "On it."
        )
        XCTAssertNil(viewModel.activePaneSession?.composerAnchor)
        XCTAssertNil(viewModel.activePaneSession?.composerReplyToCommentID)

        for _ in 0..<2_000 {
            if service.detailCallCount > detailCallsBefore {
                break
            }
            await Task.yield()
        }
        XCTAssertEqual(service.threadReplies, [
            StubPullRequestsService.ThreadReply(commentID: 987, body: "On it.")
        ])
        XCTAssertEqual(viewModel.activePaneSession?.detail?.pendingCommentCount, 0)
        // Success reconciles the placeholder against the server copy.
        XCTAssertEqual(service.detailCallCount, detailCallsBefore + 1)
    }

    func testThreadReplyFailureRemovesPlaceholderAndReopensComposer() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(Self.detailWithThread(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        service.replyResult = .failure(.requestFailed(statusCode: 502))
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))

        let thread = DiffLineCommentThread(
            comments: [
                DiffLineComment(author: "carol", bodyMarkdown: "Root", isPending: false, remoteID: 987)
            ],
            threadID: "PRT_1"
        )
        viewModel.openThreadReplyComposer(at: Self.anchor, thread: thread)
        viewModel.updateComposerText("On it.")
        viewModel.saveComposerComment()
        for _ in 0..<2_000 {
            if viewModel.activePaneSession?.composerError != nil {
                break
            }
            await Task.yield()
        }

        // The placeholder is undone and the composer reopens with the text intact.
        XCTAssertEqual(viewModel.activePaneSession?.detail?.reviewThreads.first?.comments.count, 1)
        XCTAssertEqual(viewModel.activePaneSession?.composerAnchor, Self.anchor)
        XCTAssertEqual(viewModel.activePaneSession?.composerText, "On it.")
        XCTAssertEqual(viewModel.activePaneSession?.composerReplyToCommentID, 987)
    }

    func testSetThreadResolvedAppliesOptimisticallyAndRevertsOnFailure() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(Self.detailWithThread(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))
        let detailCallsBefore = service.detailCallCount

        viewModel.setThreadResolved(threadID: "PRT_1", resolved: true)
        // The flag flips synchronously; the mutation runs behind it with no refetch.
        XCTAssertEqual(viewModel.activePaneSession?.detail?.reviewThreads.first?.isResolved, true)
        for _ in 0..<2_000 {
            if service.threadResolutions.count == 1 {
                break
            }
            await Task.yield()
        }
        XCTAssertEqual(service.threadResolutions, [
            StubPullRequestsService.ThreadResolution(threadID: "PRT_1", resolved: true)
        ])
        XCTAssertEqual(service.detailCallCount, detailCallsBefore)

        // A failing unresolve reverts the optimistic flip.
        service.resolveResult = .failure(.requestFailed(statusCode: 502))
        viewModel.setThreadResolved(threadID: "PRT_1", resolved: false)
        XCTAssertEqual(viewModel.activePaneSession?.detail?.reviewThreads.first?.isResolved, false)
        for _ in 0..<2_000 {
            if viewModel.activePaneSession?.composerError != nil {
                break
            }
            await Task.yield()
        }
        XCTAssertEqual(viewModel.activePaneSession?.detail?.reviewThreads.first?.isResolved, true)

        // A missing thread id is a no-op.
        viewModel.setThreadResolved(threadID: nil, resolved: false)
        XCTAssertEqual(service.threadResolutions.count, 2)
    }

    func testToggleReactionWithoutSubjectIDIsIgnored() {
        let service = StubPullRequestsService()
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(makePullRequestSummary(number: 7))

        // Pending local comments have no GraphQL node id.
        viewModel.toggleReaction(subjectID: nil, content: "THUMBS_UP", viewerHasReacted: false)

        XCTAssertEqual(service.reactionMutations, [])
    }

    func testReRequestReviewGuardsInFlightAndRefetchesOnSuccess() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(makePullRequestDetail(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))
        let detailCallsBefore = service.detailCallCount

        viewModel.reRequestReview(from: "carol")
        // The button disables synchronously; a second click cannot double-fire.
        XCTAssertEqual(viewModel.activePaneSession?.reRequestsInFlight, ["carol"])
        viewModel.reRequestReview(from: "carol")

        for _ in 0..<2_000 {
            if service.detailCallCount > detailCallsBefore,
               viewModel.activePaneSession?.reRequestsInFlight.isEmpty == true {
                break
            }
            await Task.yield()
        }
        XCTAssertEqual(service.reviewRequests, ["carol"])
        XCTAssertEqual(service.detailCallCount, detailCallsBefore + 1)
        XCTAssertEqual(viewModel.activePaneSession?.reRequestsInFlight, [])
    }

    func testReRequestReviewFailureSurfacesReviewersError() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(makePullRequestDetail(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        service.requestReviewResult = .failure(.requestFailed(statusCode: 422))
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))

        viewModel.reRequestReview(from: "carol")
        for _ in 0..<2_000 {
            if viewModel.activePaneSession?.reviewersError != nil {
                break
            }
            await Task.yield()
        }

        // The failure lands beside the Reviewers section (Overview), not the
        // Files-tab comment banner, and the button re-enables for a retry.
        XCTAssertNotNil(viewModel.activePaneSession?.reviewersError)
        XCTAssertNil(viewModel.activePaneSession?.composerError)
        XCTAssertEqual(viewModel.activePaneSession?.reRequestsInFlight, [])

        viewModel.clearReviewersError()
        XCTAssertNil(viewModel.activePaneSession?.reviewersError)
    }
}

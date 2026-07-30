import XCTest

@testable import Alveary

extension GitHubPullRequestsServiceTests {
    func testDetailDecodesCommentMetadataReviewsAndTimeline() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.detail)))
        let service = makeGitHubPullRequestsService(shell: shell)

        let detail = try await service.fetchDetail(PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7))

        let comment = try XCTUnwrap(detail.comments.first)
        XCTAssertEqual(comment.nodeID, "IC_bot1")
        XCTAssertTrue(comment.isBot)
        XCTAssertEqual(comment.reactions, [
            PullRequestCommentReaction(content: .heart, count: 3, viewerHasReacted: false)
        ])

        let review = try XCTUnwrap(detail.reviews.first)
        XCTAssertEqual(review.nodeID, "PRR_1")
        XCTAssertFalse(review.isBot)
        XCTAssertEqual(review.reactions, [
            PullRequestCommentReaction(content: .rocket, count: 1, viewerHasReacted: true)
        ])

        XCTAssertEqual(detail.reviewThreads.first?.nodeID, "PRT_1")

        // Null nodes drop; order is as GitHub returned it.
        XCTAssertEqual(detail.timelineEvents, Self.fixtureTimelineEvents)
    }

    /// The fixture's timeline, in GitHub's returned order.
    private static let fixtureTimelineEvents: [PullRequestTimelineEvent] = [
            PullRequestTimelineEvent(
                kind: .convertToDraft,
                actorLogin: "alice",
                actorAvatarURL: nil,
                createdAt: Date(timeIntervalSince1970: 1_782_892_800)
            ),
            PullRequestTimelineEvent(
                kind: .readyForReview,
                actorLogin: "alice",
                actorAvatarURL: nil,
                createdAt: Date(timeIntervalSince1970: 1_782_986_400)
            ),
            PullRequestTimelineEvent(
                kind: .commit,
                actorLogin: "alice",
                actorAvatarURL: nil,
                createdAt: Date(timeIntervalSince1970: 1_782_990_000),
                detail: "abc1234 Tighten parser bounds"
            ),
            PullRequestTimelineEvent(
                kind: .closed,
                actorLogin: "alice",
                actorAvatarURL: nil,
                createdAt: Date(timeIntervalSince1970: 1_782_993_600)
            ),
            PullRequestTimelineEvent(
                kind: .reopened,
                actorLogin: "alice",
                actorAvatarURL: nil,
                createdAt: Date(timeIntervalSince1970: 1_782_997_200)
            ),
            PullRequestTimelineEvent(
                kind: .reviewRequested,
                actorLogin: "alice",
                actorAvatarURL: nil,
                createdAt: Date(timeIntervalSince1970: 1_783_000_800),
                detail: "carol"
            )
        ]

    func testDetailBuildsReviewerRows() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.detail)))
        let service = makeGitHubPullRequestsService(shell: shell)

        let detail = try await service.fetchDetail(PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7))

        // Pending request first, then carol's approved verdict with re-request on.
        XCTAssertEqual(detail.reviewers, [
            PullRequestReviewer(login: "copilot", avatarURL: nil, isBot: true, state: .requested, canReRequest: false),
            PullRequestReviewer(login: "carol", avatarURL: nil, isBot: false, state: .approved, canReRequest: true)
        ])
    }

    func testMakeReviewersDeniesReRequestForBotReviews() {
        let reviewers = GitHubPullRequestsService.makeReviewers(
            requests: nil,
            reviews: [
                PullRequestReview(
                    authorLogin: "chatgpt-codex-connector",
                    authorAvatarURL: nil,
                    state: .commented,
                    bodyMarkdown: "",
                    submittedAt: nil,
                    isBot: true
                ),
                PullRequestReview(
                    authorLogin: "carol",
                    authorAvatarURL: nil,
                    state: .approved,
                    bodyMarkdown: "",
                    submittedAt: nil
                )
            ],
            pullRequestAuthor: "afollestad"
        )

        // GitHub never offers re-request for app/bot reviewers; humans keep it.
        XCTAssertEqual(reviewers, [
            PullRequestReviewer(
                login: "chatgpt-codex-connector",
                avatarURL: nil,
                isBot: true,
                state: .commented,
                canReRequest: false
            ),
            PullRequestReviewer(login: "carol", avatarURL: nil, isBot: false, state: .approved, canReRequest: true)
        ])
    }

    func testRequestReviewPostsReviewerLogin() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "{}")))
        let service = makeGitHubPullRequestsService(shell: shell)

        try await service.requestReview(
            PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7),
            reviewerLogin: "carol"
        )

        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.args, [
            "api", "repos/octo/alpha/pulls/7/requested_reviewers",
            "-X", "POST",
            "-f", "reviewers[]=carol"
        ])
    }

    func testReplyToReviewCommentPostsBody() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "{}")))
        let service = makeGitHubPullRequestsService(shell: shell)

        try await service.replyToReviewComment(
            PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7),
            commentID: 987,
            body: "Agreed, fixing."
        )

        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.args, [
            "api", "repos/octo/alpha/pulls/7/comments/987/replies",
            "-X", "POST",
            "-f", "body=Agreed, fixing."
        ])
    }

    func testSetReviewThreadResolvedSendsMatchingMutation() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: #"{"data":{}}"#)))
        await shell.enqueue(.success(pullRequestsShellResult(stdout: #"{"data":{}}"#)))
        let service = makeGitHubPullRequestsService(shell: shell)

        try await service.setReviewThreadResolved(threadID: "PRT_1", resolved: true)
        try await service.setReviewThreadResolved(threadID: "PRT_1", resolved: false)

        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 2)
        let resolve = try XCTUnwrap(invocations.first?.args.first { $0.hasPrefix("query=") })
        XCTAssertTrue(resolve.contains("resolveReviewThread"))
        let unresolve = try XCTUnwrap(invocations.last?.args.first { $0.hasPrefix("query=") })
        XCTAssertTrue(unresolve.contains("unresolveReviewThread"))
        XCTAssertTrue(invocations.allSatisfy { $0.args.contains("threadId=PRT_1") })
    }

    func testThreadMutationsDoNotRetryTransientFailures() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stderr: "gh: Bad gateway (HTTP 502)", exitCode: 1)))
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(.requestFailed(statusCode: 502)) {
            try await service.replyToReviewComment(
                PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7),
                commentID: 987,
                body: "Retry me not"
            )
        }
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 1)
    }
}

import XCTest

@testable import Alveary

final class GitHubPullRequestsServiceTests: XCTestCase {
    // MARK: - List

    func testListMapsNodesMergesBucketsAndSetsFlags() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.list)))
        let service = makeGitHubPullRequestsService(shell: shell)

        let result = try await service.listInvolvedPullRequests(buckets: allBuckets, status: nil)

        XCTAssertEqual(result.warnings, [])
        // Empty and null nodes drop out; buckets merge by id and sort newest first.
        XCTAssertEqual(result.summaries.map(\.id.number), [2, 1, 3])

        let merged = result.summaries[1]
        XCTAssertEqual(merged.id, PullRequestIdentifier(owner: "octo", repo: "alpha", number: 1))
        // The newer authored entry supplies fields; the stale requested duplicate only ORs flags.
        XCTAssertEqual(merged.title, "Add feature one")
        XCTAssertEqual(merged.status, .open)
        XCTAssertEqual(merged.authorLogin, "alice")
        XCTAssertEqual(merged.authorAvatarURL, URL(string: "https://avatars.example.com/alice"))
        XCTAssertEqual(merged.headRefName, "feat/one")
        XCTAssertEqual(merged.baseRefName, "main")
        XCTAssertEqual(merged.additions, 5)
        XCTAssertEqual(merged.deletions, 2)
        XCTAssertEqual(merged.reviewDecision, "REVIEW_REQUIRED")
        XCTAssertTrue(merged.isAuthored)
        XCTAssertTrue(merged.isReviewRequested)
        XCTAssertFalse(merged.hasReviewed)

        let draft = result.summaries[0]
        XCTAssertEqual(draft.status, .draft)
        XCTAssertEqual(draft.authorLogin, "ghost")
        XCTAssertNil(draft.authorAvatarURL)
        XCTAssertFalse(draft.isAuthored)
        XCTAssertTrue(draft.isReviewRequested)

        let reviewed = result.summaries[2]
        XCTAssertEqual(reviewed.status, .merged)
        XCTAssertTrue(reviewed.hasReviewed)
    }

    func testListSendsOneBatchedQueryWithoutRollup() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.list)))
        let service = makeGitHubPullRequestsService(shell: shell)

        _ = try await service.listInvolvedPullRequests(buckets: allBuckets, status: nil)

        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 1)
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.executable, "/opt/homebrew/bin/gh")
        XCTAssertEqual(Array(invocation.args.prefix(2)), ["api", "graphql"])
        // All three involvement buckets travel in the single batched request.
        XCTAssertTrue(invocation.args.contains("authored=is:pr author:@me sort:updated-desc"))
        XCTAssertTrue(invocation.args.contains("requested=is:pr review-requested:@me sort:updated-desc"))
        XCTAssertTrue(invocation.args.contains("reviewed=is:pr reviewed-by:@me sort:updated-desc"))
        let query = try XCTUnwrap(invocation.args.first { $0.hasPrefix("query=") })
        XCTAssertTrue(query.contains("fragment pr on PullRequest"))
        // The list intentionally skips rollup — it is the slow, 502-prone field.
        XCTAssertFalse(query.contains("statusCheckRollup"))
        XCTAssertEqual(invocation.stdoutLimitBytes, 4 * 1024 * 1024)
        XCTAssertEqual(invocation.timeout, .seconds(30))
    }

    func testListNarrowsEveryBucketToTheSelectedStatus() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.list)))
        let service = makeGitHubPullRequestsService(shell: shell)

        _ = try await service.listInvolvedPullRequests(buckets: allBuckets, status: .open)

        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        // `is:open` alone would keep drafts, which are open pull requests.
        XCTAssertTrue(invocation.args.contains("authored=is:pr is:open draft:false author:@me sort:updated-desc"))
        XCTAssertTrue(
            invocation.args.contains("requested=is:pr is:open draft:false review-requested:@me sort:updated-desc")
        )
        XCTAssertTrue(invocation.args.contains("reviewed=is:pr is:open draft:false reviewed-by:@me sort:updated-desc"))
    }

    func testListStatusQualifiersCoverEveryStatus() {
        XCTAssertEqual(PullRequestStatus.open.searchQualifier, "is:open draft:false")
        XCTAssertEqual(PullRequestStatus.draft.searchQualifier, "is:open draft:true")
        XCTAssertEqual(PullRequestStatus.merged.searchQualifier, "is:merged")
        // `is:closed` alone counts merged pull requests as closed.
        XCTAssertEqual(PullRequestStatus.closed.searchQualifier, "is:closed is:unmerged")
    }

    func testListRequestsOnlyTheBucketsAskedFor() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.list)))
        let service = makeGitHubPullRequestsService(shell: shell)

        let result = try await service.listInvolvedPullRequests(buckets: [.authored], status: nil)

        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertTrue(invocation.args.contains("authored=is:pr author:@me sort:updated-desc"))
        XCTAssertFalse(invocation.args.contains { $0.hasPrefix("requested=") })
        XCTAssertFalse(invocation.args.contains { $0.hasPrefix("reviewed=") })
        let query = try XCTUnwrap(invocation.args.first { $0.hasPrefix("query=") })
        XCTAssertTrue(query.contains("query($authored: String!)"))
        XCTAssertFalse(query.contains("requested:"))
        XCTAssertFalse(query.contains("reviewed:"))
        // The fixture carries all three buckets; only the requested one is keyed back.
        XCTAssertEqual(Set(result.summariesByBucket.keys), [.authored])
    }

    func testListKeysARequestedButForbiddenBucketAsEmptyRatherThanMissing() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(
            stdout: PullRequestsServiceFixtures.samlPartial,
            exitCode: 1
        )))
        let service = makeGitHubPullRequestsService(shell: shell)

        let result = try await service.listInvolvedPullRequests(buckets: allBuckets, status: nil)

        // A null bucket must read as fetched-and-empty; absent would have the caller refetch forever.
        XCTAssertEqual(Set(result.summariesByBucket.keys), allBuckets)
        XCTAssertEqual(result.summariesByBucket[.reviewRequested], [])
    }

    func testMergeCombinesBucketsFlagsAndSorts() {
        let older = makePullRequestSummary(
            number: 1,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            isAuthored: true
        )
        let newerSameID = makePullRequestSummary(
            number: 1,
            title: "Newer title",
            updatedAt: Date(timeIntervalSince1970: 2_000),
            isReviewRequested: true
        )
        let other = makePullRequestSummary(
            number: 2,
            updatedAt: Date(timeIntervalSince1970: 1_500),
            hasReviewed: true
        )

        let merged = PullRequestListMerge.merge([[older], [newerSameID, other]])

        XCTAssertEqual(merged.map(\.id.number), [1, 2])
        XCTAssertEqual(merged[0].title, "Newer title")
        XCTAssertTrue(merged[0].isAuthored)
        XCTAssertTrue(merged[0].isReviewRequested)
        XCTAssertFalse(merged[0].hasReviewed)
        XCTAssertTrue(merged[1].hasReviewed)
    }

    func testListToleratesPartialForbiddenResults() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.samlPartial, exitCode: 1)))
        let service = makeGitHubPullRequestsService(shell: shell)

        let result = try await service.listInvolvedPullRequests(buckets: allBuckets, status: nil)

        XCTAssertEqual(result.summaries.map(\.id.number), [1])
        XCTAssertTrue(result.summaries[0].isAuthored)
        XCTAssertEqual(result.warnings, ["Resource protected by organization SAML enforcement."])
    }

    func testListMissingCLIThrowsWithoutInvocation() async {
        let shell = MockShellRunner()
        let service = makeGitHubPullRequestsService(shell: shell, executablePath: nil)

        await assertPullRequestsServiceThrows(.ghNotInstalled) {
            _ = try await service.listInvolvedPullRequests(buckets: allBuckets, status: nil)
        }
        let invocations = await shell.invocations
        XCTAssertTrue(invocations.isEmpty)
    }

    func testListClassifiesFailures() async {
        await assertListFailure(
            .requestFailed(statusCode: 404),
            stderr: "gh: Not Found (HTTP 404)",
            exitCode: 1
        )
        await assertListFailure(
            .notAuthenticated,
            stderr: "gh: HTTP 401 Bad credentials",
            exitCode: 1
        )
        await assertListFailure(
            .notAuthenticated,
            stderr: "To get started with GitHub CLI, please run:  gh auth login",
            exitCode: 4
        )
        await assertListFailure(
            .rateLimited,
            stderr: "gh: API rate limit exceeded for user (HTTP 403)",
            exitCode: 1
        )
        await assertListFailure(
            .ghNotInstalled,
            stderr: "command not found: gh",
            exitCode: 127
        )
        await assertListFailure(
            .transport("boom"),
            stderr: "boom",
            exitCode: 1
        )
    }

    func testListRetriesTransientServerErrors() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stderr: "gh: Something went wrong (HTTP 502)", exitCode: 1)))
        await shell.enqueue(.success(pullRequestsShellResult(stderr: "gh: Bad gateway (HTTP 502)", exitCode: 1)))
        await shell.enqueue(.success(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.list)))
        let service = makeGitHubPullRequestsService(shell: shell)

        let result = try await service.listInvolvedPullRequests(buckets: allBuckets, status: nil)

        XCTAssertEqual(result.summaries.count, 3)
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 3)
    }

    func testListStopsRetryingTransientErrorsAfterLimit() async {
        let shell = MockShellRunner()
        for _ in 0..<3 {
            await shell.enqueue(.success(pullRequestsShellResult(stderr: "gh: Bad gateway (HTTP 502)", exitCode: 1)))
        }
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(.requestFailed(statusCode: 502)) {
            _ = try await service.listInvolvedPullRequests(buckets: allBuckets, status: nil)
        }
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 3)
    }

    func testListDoesNotRetryNonTransientFailures() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stderr: "gh: HTTP 401 Bad credentials", exitCode: 1)))
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(.notAuthenticated) {
            _ = try await service.listInvolvedPullRequests(buckets: allBuckets, status: nil)
        }
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 1)
    }

    func testSubmitReviewDoesNotRetryTransientFailures() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stderr: "gh: Bad gateway (HTTP 502)", exitCode: 1)))
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(.requestFailed(statusCode: 502)) {
            try await service.submitReview(
                PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7),
                event: .approve,
                body: ""
            )
        }
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 1)
    }

    func testListTruncatedResponseThrowsTooLarge() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.list, stdoutWasTruncated: true)))
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(.responseTooLarge) {
            _ = try await service.listInvolvedPullRequests(buckets: allBuckets, status: nil)
        }
    }

    func testListDecodeFailureOnSuccessExitThrowsDecodingFailed() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "not json")))
        let service = makeGitHubPullRequestsService(shell: shell)

        do {
            _ = try await service.listInvolvedPullRequests(buckets: allBuckets, status: nil)
            XCTFail("Expected an error")
        } catch let error as PullRequestsServiceError {
            guard case .decodingFailed = error else {
                return XCTFail("Expected decodingFailed, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    // MARK: - Detail

    func testDetailDecodesChecksUnionCommentsReviewsAndThreads() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.detail)))
        let service = makeGitHubPullRequestsService(shell: shell)
        let id = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)

        let detail = try await service.fetchDetail(id)

        XCTAssertEqual(detail.id, id)
        XCTAssertEqual(detail.title, "Improve parser")
        XCTAssertEqual(detail.status, .open)
        XCTAssertEqual(detail.bodyMarkdown, "## Summary\nBetter parsing.")
        XCTAssertEqual(detail.changedFiles, 3)
        XCTAssertEqual(detail.additions, 40)
        XCTAssertEqual(detail.deletions, 9)

        XCTAssertEqual(detail.checks.count, 3)
        XCTAssertEqual(detail.checks[0], PullRequestCheck(
            name: "build",
            state: .passing,
            detailsURL: URL(string: "https://ci.example.com/build")
        ))
        XCTAssertEqual(detail.checks[1].name, "test")
        XCTAssertEqual(detail.checks[1].state, .pending)
        XCTAssertEqual(detail.checks[2], PullRequestCheck(
            name: "ci/lint",
            state: .failing,
            detailsURL: URL(string: "https://ci.example.com/lint")
        ))

        XCTAssertEqual(detail.comments.count, 1)
        XCTAssertEqual(detail.comments[0].authorLogin, "helper-bot")
        XCTAssertEqual(detail.comments[0].bodyMarkdown, "Looks promising")

        XCTAssertEqual(detail.reviews.count, 1)
        XCTAssertEqual(detail.reviews[0].state, .approved)
        XCTAssertEqual(detail.reviews[0].databaseId, 555)
        XCTAssertTrue(detail.reviews[0].viewerCanUpdate)

        // A present `headRef` means the branch still exists, so Reopen stays live.
        XCTAssertTrue(detail.headRefExists)

        // The top-level `viewer` attributes local pending comments.
        XCTAssertEqual(detail.viewerLogin, "afollestad")
        XCTAssertEqual(detail.viewerAvatarURL, URL(string: "https://avatars.example.com/afollestad"))

        assertParserReviewThread(detail)

        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertTrue(invocation.args.contains("owner=octo"))
        XCTAssertTrue(invocation.args.contains("name=alpha"))
        XCTAssertTrue(invocation.args.contains("number=7"))
        XCTAssertEqual(invocation.stdoutLimitBytes, 8 * 1024 * 1024)
    }

    private func assertParserReviewThread(_ detail: PullRequestDetail, file: StaticString = #filePath, line: UInt = #line) {
        // The submitted thread plus the viewer's own pending one; pending threads
        // ride the same connection, badged by their comments' `PENDING` state.
        XCTAssertEqual(detail.reviewThreads.count, 2, file: file, line: line)
        guard let thread = detail.reviewThreads.first else {
            return
        }
        XCTAssertEqual(thread.path, "Sources/Parser.swift", file: file, line: line)
        XCTAssertEqual(thread.line, 12, file: file, line: line)
        XCTAssertEqual(thread.side, .right, file: file, line: line)
        XCTAssertFalse(thread.isResolved, file: file, line: line)
        XCTAssertTrue(thread.isOutdated, file: file, line: line)

        XCTAssertEqual(thread.comments.count, 1, file: file, line: line)
        guard let comment = thread.comments.first else {
            return
        }
        XCTAssertEqual(comment.nodeID, "PRRC_abc123", file: file, line: line)
        XCTAssertEqual(comment.databaseId, 987, file: file, line: line)
        XCTAssertTrue(comment.viewerCanUpdate, file: file, line: line)
        XCTAssertFalse(comment.viewerCanDelete, file: file, line: line)
        // The zero-count EYES group drops out.
        XCTAssertEqual(comment.reactions, [
            PullRequestCommentReaction(content: .thumbsUp, count: 2, viewerHasReacted: true)
        ], file: file, line: line)
    }

    func testDetailMissingPullRequestThrowsTransport() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: #"{"data":{"repository":{"pullRequest":null}}}"#)))
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(.transport("Pull request not found")) {
            _ = try await service.fetchDetail(PullRequestIdentifier(owner: "octo", repo: "alpha", number: 999))
        }
    }

    // MARK: - Diff

    func testDiffReturnsStdout() async throws {
        let shell = MockShellRunner()
        let diff = "diff --git a/File.swift b/File.swift\n+added\n"
        await shell.enqueue(.success(pullRequestsShellResult(stdout: diff)))
        let service = makeGitHubPullRequestsService(shell: shell)

        let output = try await service.fetchDiff(PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7))

        XCTAssertEqual(output, diff)
        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.args, ["pr", "diff", "7", "--repo", "octo/alpha"])
        XCTAssertEqual(invocation.stdoutLimitBytes, 5 * 1024 * 1024)
        XCTAssertEqual(invocation.timeout, .seconds(60))
    }

    func testDiffTruncatedThrowsTooLarge() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "diff", stdoutWasTruncated: true)))
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(.responseTooLarge) {
            _ = try await service.fetchDiff(PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7))
        }
    }

    // MARK: - Review submission

    /// Summary-only: inline comments never travel this endpoint any more, they
    /// are already attached to the pending review `submitPendingReview` finishes.
    func testSubmitReviewPostsVerdictAndSummary() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "{}")))
        let service = makeGitHubPullRequestsService(shell: shell)

        try await service.submitReview(
            PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7),
            event: .requestChanges,
            body: "Please fix the parser edge case."
        )

        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.args, [
            "api", "repos/octo/alpha/pulls/7/reviews",
            "-X", "POST",
            "-f", "event=REQUEST_CHANGES",
            "-f", "body=Please fix the parser edge case."
        ])
        // Two scalar fields need no JSON body, so no temp file is written.
        XCTAssertFalse(invocation.args.contains("--input"))
    }

    func testSubmitReviewFailureIsClassified() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stderr: "gh: Unprocessable Entity (HTTP 422)", exitCode: 1)))
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(.requestFailed(statusCode: 422)) {
            try await service.submitReview(
                PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7),
                event: .approve,
                body: ""
            )
        }
    }
}

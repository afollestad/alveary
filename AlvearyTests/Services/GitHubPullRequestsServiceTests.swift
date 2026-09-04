import XCTest

@testable import Alveary

/// List coverage lives in `GitHubPullRequestsServiceTests+List.swift`.
final class GitHubPullRequestsServiceTests: XCTestCase {
    // MARK: - Detail

    /// The rollup lists every check run on the head commit, superseded ones included, which is
    /// what showed one job six times in the pane. Collapsing must keep the newest *run* — and the
    /// fixture is built so that ordering by `startedAt` instead would pick a different, failing
    /// run for both `Release` and `flaky`, flipping their state and their link.
    func testDetailCollapsesSupersededCheckRunsKeepingTheNewestRun() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.detailDuplicateChecks)))
        let service = makeGitHubPullRequestsService(shell: shell)

        let detail = try await service.fetchDetail(PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7))

        // Nine rollup nodes collapse to five rows, ordered as github.com orders them.
        XCTAssertEqual(detail.checks.map(\.displayName), [
            "Graphite / mergeability_check",
            "legacy/status",
            "Nightly / Release",
            "PR-Auto-Merge / flaky",
            "PR-Auto-Merge / Release"
        ])

        // Run 2420 wins over 2416 and 2417 even though 2417 started latest.
        let release = try XCTUnwrap(detail.checks.first { $0.displayName == "PR-Auto-Merge / Release" })
        XCTAssertEqual(release.detailsURL, URL(string: "https://ci.example.com/release/run-2420"))
        XCTAssertEqual(release.state, .passing)

        // A job re-run inside one workflow run is separated only by the check run id.
        let flaky = try XCTUnwrap(detail.checks.first { $0.displayName == "PR-Auto-Merge / flaky" })
        XCTAssertEqual(flaky.detailsURL, URL(string: "https://ci.example.com/flaky/attempt-2"))
        XCTAssertEqual(flaky.state, .passing)

        // Same job name under a different workflow is a different check, not a duplicate.
        let nightly = try XCTUnwrap(detail.checks.first { $0.displayName == "Nightly / Release" })
        XCTAssertEqual(nightly.detailsURL, URL(string: "https://ci.example.com/nightly/release"))

        // No workflow run, so the posting app names the row.
        let graphite = try XCTUnwrap(detail.checks.first { $0.name == "mergeability_check" })
        XCTAssertEqual(graphite.workflowName, "Graphite")

        // A commit status has no run ids, so `createdAt` orders its repeats — and it stays unprefixed.
        let legacy = try XCTUnwrap(detail.checks.first { $0.name == "legacy/status" })
        XCTAssertNil(legacy.workflowName)
        XCTAssertEqual(legacy.displayName, "legacy/status")
        XCTAssertEqual(legacy.detailsURL, URL(string: "https://ci.example.com/legacy/new"))
        XCTAssertEqual(legacy.state, .passing)

        // Rows must be distinguishable to SwiftUI now that identity is not the array index.
        XCTAssertEqual(Set(detail.checks.map(\.id)).count, detail.checks.count)
    }

    /// Pins the rollup selection `makeChecks` depends on. Without these fields it still compiles
    /// and still returns rows, but silently keeps an arbitrary run and drops every workflow label
    /// — a regression no other assertion here would catch.
    func testDetailQuerySelectsTheFieldsCheckDedupNeeds() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.detail)))
        let service = makeGitHubPullRequestsService(shell: shell)

        _ = try await service.fetchDetail(PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7))

        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        let query = try XCTUnwrap(invocation.args.first { $0.hasPrefix("query=") })
        XCTAssertTrue(query.contains("workflowRun { databaseId workflow { name } }"))
        XCTAssertTrue(query.contains("app { name }"))
        // GitHub caps this connection at 100, and dedup runs after the page, so a smaller page
        // drops real checks that superseded runs crowded out.
        XCTAssertTrue(query.contains("contexts(first: 100)"))
    }

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

        // Alphabetical by display name, so `ci/lint` sorts ahead of the `test` check run.
        XCTAssertEqual(detail.checks.map(\.displayName), ["build", "ci/lint", "test"])
        XCTAssertEqual(detail.checks[0], PullRequestCheck(
            name: "build",
            state: .passing,
            detailsURL: URL(string: "https://ci.example.com/build")
        ))
        XCTAssertEqual(detail.checks[1], PullRequestCheck(
            name: "ci/lint",
            state: .failing,
            detailsURL: URL(string: "https://ci.example.com/lint")
        ))
        XCTAssertEqual(detail.checks[2].name, "test")
        XCTAssertEqual(detail.checks[2].state, .pending)

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
        XCTAssertEqual(invocation.timeout, .seconds(20))
        XCTAssertEqual(invocation.standardInput, .nullDevice)
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
        // Diff stays pane-sized; it has no retry budget to sit under.
        XCTAssertEqual(invocation.timeout, .seconds(60))
        XCTAssertEqual(invocation.standardInput, .nullDevice)
    }

    func testRawDiffTruncatedThrowsTooLarge() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "diff", stdoutWasTruncated: true)))
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(.responseTooLarge) {
            _ = try await service.fetchRawDiff(PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7))
        }
    }

    // MARK: - Review submission

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

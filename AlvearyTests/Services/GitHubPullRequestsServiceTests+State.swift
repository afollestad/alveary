import XCTest

@testable import Alveary

// Closing and reopening the pull request itself: a `state` PATCH on the pull,
// plus the `headRef` presence that gates reopening.
extension GitHubPullRequestsServiceTests {
    func testClosePullRequestPatchesStateClosed() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "{}")))
        let service = makeGitHubPullRequestsService(shell: shell)

        try await service.setPullRequestClosed(
            PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7),
            closed: true
        )

        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.args, [
            "api", "repos/octo/alpha/pulls/7",
            "-X", "PATCH",
            "-f", "state=closed"
        ])
        XCTAssertEqual(invocations.count, 1)
    }

    func testReopenPullRequestPatchesStateOpen() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "{}")))
        let service = makeGitHubPullRequestsService(shell: shell)

        try await service.setPullRequestClosed(
            PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7),
            closed: false
        )

        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.args, [
            "api", "repos/octo/alpha/pulls/7",
            "-X", "PATCH",
            "-f", "state=open"
        ])
    }

    func testMarkReadyForReviewSendsGraphQLMutation() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "{}")))
        let service = makeGitHubPullRequestsService(shell: shell)

        try await service.markPullRequestReadyForReview(nodeID: "PR_41")

        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.args.first, "api")
        XCTAssertEqual(invocation.args.dropFirst().first, "graphql")
        XCTAssertTrue(invocation.args.contains { $0.contains("markPullRequestReadyForReview") })
        XCTAssertTrue(invocation.args.contains("pullRequestId=PR_41"))
        XCTAssertEqual(invocations.count, 1)
    }

    func testMarkReadyForReviewFailureIsClassified() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stderr: "gh: Not Found (HTTP 404)", exitCode: 1)))
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(.requestFailed(statusCode: 404)) {
            try await service.markPullRequestReadyForReview(nodeID: "PR_41")
        }
    }

    func testConvertToDraftSendsGraphQLMutation() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "{}")))
        let service = makeGitHubPullRequestsService(shell: shell)

        try await service.convertPullRequestToDraft(nodeID: "PR_41")

        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.args.first, "api")
        XCTAssertEqual(invocation.args.dropFirst().first, "graphql")
        XCTAssertTrue(invocation.args.contains { $0.contains("convertPullRequestToDraft") })
        XCTAssertTrue(invocation.args.contains("pullRequestId=PR_41"))
        XCTAssertEqual(invocations.count, 1)
    }

    func testConvertToDraftFailureIsClassified() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stderr: "gh: Not Found (HTTP 404)", exitCode: 1)))
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(.requestFailed(statusCode: 404)) {
            try await service.convertPullRequestToDraft(nodeID: "PR_41")
        }
    }

    func testStateChangeFailureIsClassified() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stderr: "gh: Unprocessable Entity (HTTP 422)", exitCode: 1)))
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(.requestFailed(statusCode: 422)) {
            try await service.setPullRequestClosed(
                PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7),
                closed: false
            )
        }
    }

    func testDetailWithDeletedHeadBranchReportsMissingRef() async throws {
        // GitHub nulls `headRef` once the branch is gone while keeping the name.
        let payload = PullRequestsServiceFixtures.detail.replacingOccurrences(
            of: #""headRef": { "name": "feat/parser" },"#,
            with: #""headRef": null,"#
        )
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: payload)))
        let service = makeGitHubPullRequestsService(shell: shell)

        let detail = try await service.fetchDetail(PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7))

        XCTAssertFalse(detail.headRefExists)
        XCTAssertEqual(detail.headRefName, "feat/parser")
    }
}

import XCTest

@testable import Alveary

// Comment mutation endpoints: review-thread comments live under `pulls/comments`,
// top-level conversation comments under `issues/comments`. Mutations never retry.
extension GitHubPullRequestsServiceTests {
    func testUpdateReviewCommentPatchesBody() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "{}")))
        let service = makeGitHubPullRequestsService(shell: shell)

        try await service.updateReviewComment(
            PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7),
            commentID: 987,
            body: "Updated body"
        )

        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.args, [
            "api", "repos/octo/alpha/pulls/comments/987",
            "-X", "PATCH",
            "-f", "body=Updated body"
        ])
    }

    func testDeleteReviewCommentSendsDelete() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "")))
        let service = makeGitHubPullRequestsService(shell: shell)

        try await service.deleteReviewComment(
            PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7),
            commentID: 654
        )

        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.args, [
            "api", "repos/octo/alpha/pulls/comments/654",
            "-X", "DELETE"
        ])
        XCTAssertEqual(invocations.count, 1)
    }

    func testUpdateReviewPutsBodyThroughReviewsEndpoint() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "{}")))
        let service = makeGitHubPullRequestsService(shell: shell)

        try await service.updateReview(
            PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7),
            reviewID: 555,
            body: "Updated summary"
        )

        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.args, [
            "api", "repos/octo/alpha/pulls/7/reviews/555",
            "-X", "PUT",
            "-f", "body=Updated summary"
        ])
        XCTAssertEqual(invocations.count, 1)
    }

    func testUpdateIssueCommentPatchesBodyThroughIssuesEndpoint() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "{}")))
        let service = makeGitHubPullRequestsService(shell: shell)

        try await service.updateIssueComment(
            PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7),
            commentID: 321,
            body: "Updated body"
        )

        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.args, [
            "api", "repos/octo/alpha/issues/comments/321",
            "-X", "PATCH",
            "-f", "body=Updated body"
        ])
    }

    func testDeleteIssueCommentSendsDeleteThroughIssuesEndpoint() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "")))
        let service = makeGitHubPullRequestsService(shell: shell)

        try await service.deleteIssueComment(
            PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7),
            commentID: 321
        )

        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.args, [
            "api", "repos/octo/alpha/issues/comments/321",
            "-X", "DELETE"
        ])
        XCTAssertEqual(invocations.count, 1)
    }

    func testUpdateReviewCommentDoesNotRetryTransientFailures() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stderr: "gh: Bad gateway (HTTP 502)", exitCode: 1)))
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(.requestFailed(statusCode: 502)) {
            try await service.updateReviewComment(
                PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7),
                commentID: 987,
                body: "Updated body"
            )
        }
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 1)
    }
}

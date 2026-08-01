import Foundation
import XCTest

@testable import Alveary

extension GitHubPullRequestsServiceTests {
    /// `pr create` is the one call that runs in the worktree — the repository
    /// comes from the directory, not a `--repo` flag — and must never take
    /// interactive input.
    func testCreatePullRequestRunsInTheDirectoryWithArgvContent() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(
            .success(pullRequestsShellResult(stdout: "https://github.com/octo/alpha/pull/41\n"))
        )
        let service = makeGitHubPullRequestsService(shell: shell)

        let identifier = try await service.createPullRequest(
            inDirectory: "/tmp/worktree",
            baseBranch: "main",
            headBranch: "alveary/feature",
            title: "Add caching",
            body: "Caches responses."
        )

        XCTAssertEqual(identifier, PullRequestIdentifier(owner: "octo", repo: "alpha", number: 41))
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 1)
        XCTAssertEqual(invocations[0].args, [
            "pr", "create",
            "--base", "main",
            "--head", "alveary/feature",
            "--title", "Add caching",
            "--body", "Caches responses."
        ])
        XCTAssertEqual(invocations[0].directory, "/tmp/worktree")
        XCTAssertEqual(invocations[0].standardInput, .nullDevice)
    }

    /// `gh` can print progress notes before the URL; the identifier comes from
    /// the last URL-shaped line.
    func testCreatePullRequestParsesTheLastURLLine() {
        let stdout = """
        Creating pull request for alveary/feature into main in octo/alpha

        https://github.com/octo/alpha/pull/41
        """
        XCTAssertEqual(
            GitHubPullRequestsService.parseCreatedPullRequestIdentifier(fromStdout: stdout),
            PullRequestIdentifier(owner: "octo", repo: "alpha", number: 41)
        )
        XCTAssertNil(GitHubPullRequestsService.parseCreatedPullRequestIdentifier(fromStdout: "no url here"))
    }

    func testCreatePullRequestWithoutAURLFailsAsDecoding() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "created, but no url\n")))
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(
            .decodingFailed("gh pr create did not print the new pull request's URL")
        ) {
            _ = try await service.createPullRequest(
                inDirectory: "/tmp/worktree",
                baseBranch: "main",
                headBranch: "alveary/feature",
                title: "Title",
                body: "Body"
            )
        }
    }

    func testCreatePullRequestSurfacesGitHubFailures() async {
        let shell = MockShellRunner()
        await shell.enqueue(
            .success(pullRequestsShellResult(stderr: "HTTP 422: Validation Failed", exitCode: 1))
        )
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(.requestFailed(statusCode: 422)) {
            _ = try await service.createPullRequest(
                inDirectory: "/tmp/worktree",
                baseBranch: "main",
                headBranch: "alveary/feature",
                title: "Title",
                body: "Body"
            )
        }
    }
}

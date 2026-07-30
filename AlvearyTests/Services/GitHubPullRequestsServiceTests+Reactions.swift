import XCTest

@testable import Alveary

extension GitHubPullRequestsServiceTests {
    func testReactionMutationsSendSubjectAndContent() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: #"{"data":{}}"#)))
        await shell.enqueue(.success(pullRequestsShellResult(stdout: #"{"data":{}}"#)))
        let service = makeGitHubPullRequestsService(shell: shell)

        try await service.addReaction(subjectID: "PRRC_abc123", content: .hooray)
        try await service.removeReaction(subjectID: "PRRC_abc123", content: .thumbsUp)

        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 2)
        let add = try XCTUnwrap(invocations.first)
        XCTAssertEqual(Array(add.args.prefix(2)), ["api", "graphql"])
        XCTAssertTrue(try XCTUnwrap(add.args.first { $0.hasPrefix("query=") }).contains("addReaction"))
        XCTAssertTrue(add.args.contains("subjectId=PRRC_abc123"))
        XCTAssertTrue(add.args.contains("content=HOORAY"))
        let remove = try XCTUnwrap(invocations.last)
        XCTAssertTrue(try XCTUnwrap(remove.args.first { $0.hasPrefix("query=") }).contains("removeReaction"))
        XCTAssertTrue(remove.args.contains("content=THUMBS_UP"))
    }

    func testReactionMutationDoesNotRetryTransientFailures() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stderr: "gh: Bad gateway (HTTP 502)", exitCode: 1)))
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(.requestFailed(statusCode: 502)) {
            try await service.addReaction(subjectID: "PRRC_abc123", content: .eyes)
        }
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 1)
    }
}

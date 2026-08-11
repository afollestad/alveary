import XCTest

@testable import Alveary

extension GitHubPullRequestsServiceTests {
    // A single bucket so the queue stays deterministic: a fan-out's legs consume it in whatever
    // order the task group schedules them.
    func testListRetriesTransientServerErrors() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stderr: "gh: Something went wrong (HTTP 502)", exitCode: 1)))
        await shell.enqueue(.success(pullRequestsShellResult(stderr: "gh: Bad gateway (HTTP 502)", exitCode: 1)))
        await shell.enqueue(.success(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.list)))
        let service = makeGitHubPullRequestsService(shell: shell)

        let result = try await service.listInvolvedPullRequests(buckets: [.authored], status: nil, options: .firstPage)

        XCTAssertEqual(result.summaries.map(\.id.number), [1])
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 3)
    }

    func testListStopsRetryingTransientErrorsAfterLimit() async {
        let shell = makeUniformShellRunner(
            pullRequestsShellResult(stderr: "gh: Bad gateway (HTTP 502)", exitCode: 1)
        )
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(.requestFailed(statusCode: 502)) {
            _ = try await service.listInvolvedPullRequests(buckets: [.authored], status: nil, options: .firstPage)
        }
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 3)
    }

    func testListDoesNotRetryNonTransientFailures() async {
        let shell = makeUniformShellRunner(
            pullRequestsShellResult(stderr: "gh: HTTP 401 Bad credentials", exitCode: 1)
        )
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(.notAuthenticated) {
            _ = try await service.listInvolvedPullRequests(buckets: [.authored], status: nil, options: .firstPage)
        }
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 1)
    }

    /// GitHub states an over-expensive query in the GraphQL body with no HTTP status, so without
    /// its own case it lands in `.transport` and its raw sentence is shown to the user.
    func testListClassifiesGitHubRefusingAnOverExpensiveQuery() async {
        let body = """
        {"data":null,"errors":[{"message":"Resource limits for this query exceeded. \
        Please reduce the number of requested items."}]}
        """
        let shell = makeUniformShellRunner(pullRequestsShellResult(stdout: body, exitCode: 1))
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(.queryTooExpensive) {
            _ = try await service.listInvolvedPullRequests(buckets: [.authored], status: nil, options: .firstPage)
        }
        // Retrying an identical query GitHub refused to run costs the same and fails the same way.
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 1)
    }

    /// The last retry runs on a timeout this service shortened, so its timing out says nothing the
    /// caller can act on — while the 5xx that caused the retry does. Any thrown shell error
    /// reproduces it: `runGitHubCLI` wraps everything that is not already a service error into
    /// `.transport`, which is exactly the substitution being prevented.
    func testAFinalRetryTimingOutKeepsTheNamedServerFailure() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stderr: "gh: Something went wrong (HTTP 504)", exitCode: 1)))
        await shell.enqueue(.success(pullRequestsShellResult(stderr: "gh: Gateway timeout (HTTP 504)", exitCode: 1)))
        await shell.enqueue(.failure(.message("gh timed out after 3 seconds")))
        let service = makeGitHubPullRequestsService(shell: shell)

        await assertPullRequestsServiceThrows(.requestFailed(statusCode: 504)) {
            _ = try await service.listInvolvedPullRequests(buckets: [.authored], status: nil, options: .firstPage)
        }
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 3)
    }

    /// A shell error with no earlier transient failure to fall back on still propagates.
    func testAFirstAttemptShellFailureStillSurfaces() async {
        let shell = MockShellRunner()
        await shell.enqueue(.failure(.message("gh timed out after 20 seconds")))
        let service = makeGitHubPullRequestsService(shell: shell)

        do {
            _ = try await service.listInvolvedPullRequests(buckets: [.authored], status: nil, options: .firstPage)
            XCTFail("Expected the shell failure to propagate")
        } catch let error as PullRequestsServiceError {
            // The wording comes from the thrown error's `localizedDescription`, which is the
            // mock's concern; what matters is that nothing swallowed it.
            guard case .transport = error else {
                return XCTFail("Expected .transport, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    /// `gh` puts other numbers on stderr, and one landing before the status used to be returned as
    /// the status — which read a retryable 502 as a non-retryable 128 and skipped the retry.
    func testHTTPStatusReadsTheMarkerRatherThanTheFirstNumberPresent() {
        XCTAssertEqual(
            GitHubPullRequestsService.httpStatusCode(in: "gh: failed to run git: exit 128\ngh: Bad gateway (HTTP 502)"),
            502
        )
        XCTAssertEqual(GitHubPullRequestsService.httpStatusCode(in: "gh: Not Found (HTTP 404)"), 404)
        XCTAssertNil(GitHubPullRequestsService.httpStatusCode(in: "gh: pull request 342 not found"))
    }

    /// The retry budget stops short rather than letting an attempt run past the caller's deadline,
    /// where its named failure would be replaced by a generic timeout.
    func testNextRetryAttemptTimeoutFitsTheRemainingBudget() {
        XCTAssertEqual(
            GitHubPullRequestsService.nextRetryAttemptTimeout(
                elapsed: .zero,
                nextBackoff: .milliseconds(400),
                attemptTimeout: .seconds(20),
                budget: .seconds(25)
            ),
            .seconds(20)
        )
        // Less budget than one full attempt: shorten rather than overrun.
        XCTAssertEqual(
            GitHubPullRequestsService.nextRetryAttemptTimeout(
                elapsed: .seconds(18),
                nextBackoff: .milliseconds(500),
                attemptTimeout: .seconds(20),
                budget: .seconds(25)
            ),
            .milliseconds(6_500)
        )
        // Below `minimumRetryAttemptTimeout` an attempt can only time out, so stop.
        XCTAssertNil(GitHubPullRequestsService.nextRetryAttemptTimeout(
            elapsed: .seconds(24),
            nextBackoff: .milliseconds(400),
            attemptTimeout: .seconds(20),
            budget: .seconds(25)
        ))
        // The tail of the budget is not enough for a real request, which measures around four
        // seconds — spending it produces a timeout that buries the failure already in hand.
        XCTAssertNil(GitHubPullRequestsService.nextRetryAttemptTimeout(
            elapsed: .seconds(21),
            nextBackoff: .milliseconds(800),
            attemptTimeout: .seconds(20),
            budget: .seconds(25)
        ))
    }
}

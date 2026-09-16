import Darwin
import Foundation
import XCTest

@testable import Alveary

extension GitHubPullRequestsServiceTests {
    func testSubmissionAfterRateLimitPreservesLaunchDiagnosticWithoutAutomaticRetry() async {
        for pending in [false, true] {
            let shell = ReviewSubmissionLaunchFailureShellRunner()
            let service = GitHubPullRequestsService(
                shellRunner: shell,
                executableResolver: PullRequestsExecutablePathResolverFake(path: "/opt/homebrew/bin/gh"),
                transientRetryDelay: .zero
            )
            let submit = {
                if pending {
                    try await service.submitPendingReview(reviewNodeID: "pending-review", event: .comment, body: "private-review-body")
                } else {
                    try await service.submitReview(
                        PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7), event: .comment, body: "private-review-body"
                    )
                }
            }

            await assertPullRequestsServiceThrows(.rateLimited, submit)
            do {
                try await submit()
                XCTFail("Expected the next user submission to report the launch failure")
            } catch let error as PullRequestsServiceError {
                XCTAssertTrue(error.localizedDescription.contains("Could not launch /opt/homebrew/bin/gh"))
                XCTAssertTrue(error.localizedDescription.contains("NSPOSIXErrorDomain, code 9"))
                XCTAssertFalse(error.localizedDescription.contains("private-review-body"))
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
            let calls = await shell.callCount
            XCTAssertEqual(calls, 2, "Each user submission must invoke gh only once.")
        }
    }
}

/// Simulates a GitHub rejection followed by a local failure before a subsequent user submission can start.
private actor ReviewSubmissionLaunchFailureShellRunner: ShellRunner {
    private(set) var callCount = 0

    func run(executable: String, args: [String], in directory: String?, options: ShellRunOptions) async throws -> ShellResult {
        callCount += 1
        if callCount == 1 {
            return pullRequestsShellResult(stderr: "gh: API rate limit exceeded (HTTP 403)", exitCode: 1)
        }
        throw ShellError.launchFailed(
            executable: executable, domain: NSPOSIXErrorDomain, code: Int(EBADF), reason: "Bad file descriptor"
        )
    }
}

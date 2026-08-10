import Foundation
import XCTest

@testable import Alveary

/// Every involvement bucket, which is what the All tab asks for.
let allBuckets = Set(PullRequestInvolvementBucket.allCases)

func makeGitHubPullRequestsService(
    shell: MockShellRunner,
    executablePath: String? = "/opt/homebrew/bin/gh"
) -> GitHubPullRequestsService {
    GitHubPullRequestsService(
        shellRunner: shell,
        executableResolver: PullRequestsExecutablePathResolverFake(path: executablePath),
        transientRetryDelay: .zero
    )
}

/// A runner that answers *every* invocation the same way, which is what a multi-bucket list needs:
/// its legs fan out, so a single queued response would only reach whichever leg ran first.
func makeUniformShellRunner(_ result: ShellResult) -> MockShellRunner {
    MockShellRunner(defaultResponse: .success(result))
}

func assertListFailure(
    _ expected: PullRequestsServiceError,
    stderr: String,
    exitCode: Int32,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let shell = makeUniformShellRunner(pullRequestsShellResult(stderr: stderr, exitCode: exitCode))
    let service = makeGitHubPullRequestsService(shell: shell)

    do {
        _ = try await service.listInvolvedPullRequests(buckets: allBuckets, status: nil)
        XCTFail("Expected \(expected)", file: file, line: line)
    } catch let error as PullRequestsServiceError {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("Unexpected error \(error)", file: file, line: line)
    }
}

func assertPullRequestsServiceThrows(
    _ expected: PullRequestsServiceError,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: () async throws -> Void
) async {
    do {
        try await body()
        XCTFail("Expected \(expected)", file: file, line: line)
    } catch let error as PullRequestsServiceError {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("Unexpected error \(error)", file: file, line: line)
    }
}

/// The one `-f <bucket>=<query>` argument a fan-out leg carries, naming which bucket it searched.
func searchArgument(_ invocation: MockShellRunner.Invocation) -> String? {
    invocation.args.first(where: isSearchArgument)
}

func isSearchArgument(_ argument: String) -> Bool {
    PullRequestInvolvementBucket.allCases.contains { argument.hasPrefix("\($0.queryVariableName)=") }
}

func pullRequestsShellResult(
    stdout: String = "",
    stderr: String = "",
    exitCode: Int32 = 0,
    stdoutWasTruncated: Bool = false
) -> ShellResult {
    ShellResult(
        stdout: stdout,
        stderr: stderr,
        exitCode: exitCode,
        stdoutWasTruncated: stdoutWasTruncated,
        stderrWasTruncated: false
    )
}

struct PullRequestsExecutablePathResolverFake: ExecutablePathResolving {
    let path: String?

    func resolveExecutablePath(for candidate: String) async -> String? {
        XCTAssertEqual(candidate, "gh")
        return path
    }
}

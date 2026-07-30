import Foundation
import XCTest

@testable import Alveary

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

func assertListFailure(
    _ expected: PullRequestsServiceError,
    stderr: String,
    exitCode: Int32,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let shell = MockShellRunner()
    await shell.enqueue(.success(pullRequestsShellResult(stderr: stderr, exitCode: exitCode)))
    let service = makeGitHubPullRequestsService(shell: shell)

    do {
        _ = try await service.listInvolvedPullRequests()
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

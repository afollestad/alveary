import Foundation
import XCTest

@testable import Alveary

@MainActor
extension WorktreeManagerTests {
    func testMakeGitErrorExplainsMissingGitLFSFromStderr() {
        let result = ShellResult(
            stdout: "",
            stderr: """
            git-lfs filter-process: git-lfs: command not found
            fatal: the remote end hung up unexpectedly
            """,
            exitCode: 128,
            stdoutWasTruncated: false,
            stderrWasTruncated: false
        )

        let error = DefaultWorktreeManager.makeGitError(from: result)

        guard case .commandFailed(let message) = error else {
            return XCTFail("Expected command failure")
        }
        XCTAssertTrue(message.contains("Git LFS is required to check out this repository"))
        XCTAssertTrue(message.contains("not installed or is not available in Alveary's PATH"))
        XCTAssertTrue(message.contains("brew install git-lfs"))
        XCTAssertTrue(message.contains("git lfs install"))
        XCTAssertTrue(message.contains("Original Git error: git-lfs filter-process: git-lfs: command not found"))
        XCTAssertTrue(message.contains("fatal: the remote end hung up unexpectedly"))
    }

    func testMakeGitErrorExplainsMissingGitLFSFromStdout() {
        let result = ShellResult(
            stdout: "git-lfs filter-process: git-lfs: command not found",
            stderr: "",
            exitCode: 128,
            stdoutWasTruncated: false,
            stderrWasTruncated: false
        )

        let error = DefaultWorktreeManager.makeGitError(from: result)

        guard case .commandFailed(let message) = error else {
            return XCTFail("Expected command failure")
        }
        XCTAssertTrue(message.contains("Git LFS is required to check out this repository"))
        XCTAssertTrue(message.contains("not installed or is not available in Alveary's PATH"))
        XCTAssertTrue(message.contains("Original Git error: git-lfs filter-process: git-lfs: command not found"))
    }
}

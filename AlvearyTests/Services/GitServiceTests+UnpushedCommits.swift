import Foundation
import XCTest

@testable import Alveary

extension GitServiceTests {
    private func shellResult(stdout: String = "", exitCode: Int32 = 0) -> ShellResult {
        ShellResult(
            stdout: stdout,
            stderr: "",
            exitCode: exitCode,
            stdoutWasTruncated: false,
            stderrWasTruncated: false
        )
    }

    /// With an upstream, "unpushed" is the `upstream..HEAD` count and the base
    /// branch never enters the picture.
    func testHasUnpushedCommitsCountsAgainstTheUpstream() async throws {
        let shell = MockShellRunner()
        // 1: rev-parse @{upstream} -> the branch tracks origin/feature.
        await shell.enqueue(.success(shellResult(stdout: "origin/feature\n")))
        // 2: rev-list origin/feature..HEAD --count -> two unpushed commits.
        await shell.enqueue(.success(shellResult(stdout: "2\n")))
        let service = CLIGitService(shell: shell)

        let hasUnpushed = try await service.hasUnpushedCommits(
            baseBranch: "main",
            remoteName: "origin",
            in: "/tmp/project"
        )

        XCTAssertTrue(hasUnpushed)
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 2)
        XCTAssertEqual(invocations[1].args, ["rev-list", "origin/feature..HEAD", "--count"])
    }

    func testHasUnpushedCommitsIsFalseOnceTheUpstreamIsCurrent() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(shellResult(stdout: "origin/feature\n")))
        await shell.enqueue(.success(shellResult(stdout: "0\n")))
        let service = CLIGitService(shell: shell)

        let hasUnpushed = try await service.hasUnpushedCommits(
            baseBranch: "main",
            remoteName: "origin",
            in: "/tmp/project"
        )

        XCTAssertFalse(hasUnpushed)
    }

    /// A never-pushed branch falls back to the ahead-of-base count: ahead means
    /// a first push is meaningful.
    func testHasUnpushedCommitsWithoutAnUpstreamFallsBackToAheadOfBase() async throws {
        let shell = MockShellRunner()
        // 1: rev-parse @{upstream} fails -> no upstream.
        await shell.enqueue(.success(shellResult(exitCode: 128)))
        // 2: symbolic-ref refs/remotes/origin/HEAD -> the recorded default.
        await shell.enqueue(.success(shellResult(stdout: "refs/remotes/origin/main\n")))
        // 3: rev-list origin/main..HEAD --count -> three commits ahead of base.
        await shell.enqueue(.success(shellResult(stdout: "3\n")))
        let service = CLIGitService(shell: shell)

        let hasUnpushed = try await service.hasUnpushedCommits(
            baseBranch: "main",
            remoteName: "origin",
            in: "/tmp/project"
        )

        XCTAssertTrue(hasUnpushed)
        let invocations = await shell.invocations
        XCTAssertEqual(invocations[2].args, ["rev-list", "origin/main..HEAD", "--count"])
    }

    /// No upstream and sitting exactly on base: pushing would only mirror the
    /// base branch, so nothing counts as unpushed.
    func testHasUnpushedCommitsWithoutAnUpstreamOnBaseIsFalse() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(shellResult(exitCode: 128)))
        await shell.enqueue(.success(shellResult(stdout: "refs/remotes/origin/main\n")))
        await shell.enqueue(.success(shellResult(stdout: "0\n")))
        let service = CLIGitService(shell: shell)

        let hasUnpushed = try await service.hasUnpushedCommits(
            baseBranch: "main",
            remoteName: "origin",
            in: "/tmp/project"
        )

        XCTAssertFalse(hasUnpushed)
    }
}

import XCTest

@testable import Alveary

extension GitServiceTests {
    /// The recorded default branch wins over the caller's persisted hint. This
    /// is the whole point of the resolution: `Project.baseRef` is captured once
    /// at import, so a stale value used to turn the commit list into "commits
    /// not yet pushed".
    func testCommitsAheadOfBaseDetailsPrefersRecordedDefaultBranchOverPersistedHint() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(Self.shellResult(stdout: "refs/remotes/origin/main\n")))
        await shell.enqueue(
            .success(
                Self.shellResult(stdout: "abc123\nAdd feature\nAlice\n2024-01-01T12:34:56Z")
            )
        )

        let service = CLIGitService(shell: shell)

        let commits = try await service.commitsAheadOfBaseDetails(
            baseBranch: "feature/stale-import",
            remoteName: "origin",
            in: "/tmp/project"
        )

        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits.first?.hash, "abc123")
        XCTAssertEqual(commits.first?.message, "Add feature")

        let invocations = await shell.invocations
        XCTAssertEqual(invocations[0].args, ["symbolic-ref", "refs/remotes/origin/HEAD"])
        XCTAssertEqual(invocations[1].args, ["log", "--pretty=format:%H%n%s%n%an%n%aI", "origin/main..HEAD"])
    }

    /// Only `git clone` writes `refs/remotes/<remote>/HEAD`, so a clone without
    /// it falls through to the conventional names rather than the stale hint.
    func testCommitsAheadOfBaseDetailsProbesConventionalNamesWhenRemoteHeadIsMissing() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(Self.shellResult(exitCode: 1)))
        await shell.enqueue(.success(Self.shellResult()))
        await shell.enqueue(
            .success(
                Self.shellResult(stdout: "def456\nFix bug\nBob\n2024-01-02T12:34:56Z")
            )
        )

        let service = CLIGitService(shell: shell)

        let commits = try await service.commitsAheadOfBaseDetails(
            baseBranch: "feature/stale-import",
            remoteName: "origin",
            in: "/tmp/project"
        )

        XCTAssertEqual(commits.first?.hash, "def456")

        let invocations = await shell.invocations
        XCTAssertEqual(invocations[0].args, ["symbolic-ref", "refs/remotes/origin/HEAD"])
        XCTAssertEqual(invocations[1].args, ["show-ref", "--verify", "--quiet", "refs/remotes/origin/main"])
        XCTAssertEqual(invocations[2].args, ["log", "--pretty=format:%H%n%s%n%an%n%aI", "origin/main..HEAD"])
    }

    /// A Task thread carries no project, so no remote name. Reading the remote
    /// from the repository is what keeps it off the branch upstream, which would
    /// list only unpushed commits.
    func testCommitsAheadOfBaseDetailsReadsRemoteFromRepositoryWhenRemoteNameIsMissing() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(Self.shellResult(stdout: "origin\n")))
        await shell.enqueue(.success(Self.shellResult(stdout: "refs/remotes/origin/main\n")))
        await shell.enqueue(
            .success(
                Self.shellResult(stdout: "abc123\nAdd local work\nAlice\n2024-01-01T12:34:56Z")
            )
        )

        let service = CLIGitService(shell: shell)

        let commits = try await service.commitsAheadOfBaseDetails(
            baseBranch: "main",
            remoteName: nil,
            in: "/tmp/project"
        )

        XCTAssertEqual(commits.first?.hash, "abc123")

        let invocations = await shell.invocations
        XCTAssertEqual(invocations[0].args, ["remote"])
        XCTAssertEqual(invocations[1].args, ["symbolic-ref", "refs/remotes/origin/HEAD"])
        XCTAssertEqual(invocations[2].args, ["log", "--pretty=format:%H%n%s%n%an%n%aI", "origin/main..HEAD"])
    }

    /// With no remote at all the local default branch is still a better
    /// comparison than the upstream, which does not exist either.
    func testCommitsAheadOfBaseDetailsFallsBackToLocalDefaultBranchWithoutARemote() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(Self.shellResult(exitCode: 1)))
        await shell.enqueue(.success(Self.shellResult()))
        await shell.enqueue(
            .success(
                Self.shellResult(stdout: "def456\nFix local work\nBob\n2024-01-02T12:34:56Z")
            )
        )

        let service = CLIGitService(shell: shell)

        let commits = try await service.commitsAheadOfBaseDetails(
            baseBranch: "feature/stale-import",
            remoteName: nil,
            in: "/tmp/project"
        )

        XCTAssertEqual(commits.first?.hash, "def456")

        let invocations = await shell.invocations
        XCTAssertEqual(invocations[0].args, ["remote"])
        XCTAssertEqual(invocations[1].args, ["show-ref", "--verify", "--quiet", "refs/heads/main"])
        XCTAssertEqual(invocations[2].args, ["log", "--pretty=format:%H%n%s%n%an%n%aI", "main..HEAD"])
    }

    /// Nothing discoverable, so the caller's persisted hint is used after all.
    func testCommitsAheadOfBaseDetailsFallsBackToPersistedHintWhenNoDefaultResolves() async throws {
        let shell = MockShellRunner()
        // `git remote`, then both conventional local probes, all failing.
        for _ in 0..<3 {
            await shell.enqueue(.success(Self.shellResult(exitCode: 1)))
        }
        // The hint's own local ref exists.
        await shell.enqueue(.success(Self.shellResult()))
        await shell.enqueue(
            .success(
                Self.shellResult(stdout: "abc999\nWork\nAlice\n2024-01-03T12:34:56Z")
            )
        )

        let service = CLIGitService(shell: shell)

        let commits = try await service.commitsAheadOfBaseDetails(
            baseBranch: "develop",
            remoteName: nil,
            in: "/tmp/project"
        )

        XCTAssertEqual(commits.first?.hash, "abc999")

        let invocations = await shell.invocations
        XCTAssertEqual(invocations[3].args, ["show-ref", "--verify", "--quiet", "refs/heads/develop"])
        XCTAssertEqual(invocations[4].args, ["log", "--pretty=format:%H%n%s%n%an%n%aI", "develop..HEAD"])
    }

    func testAheadCountAndDetailsUseSameInferredCompareRef() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(Self.shellResult(stdout: "origin\n")))
        await shell.enqueue(.success(Self.shellResult(stdout: "refs/remotes/origin/main\n")))
        await shell.enqueue(.success(Self.shellResult(stdout: "3\n")))
        await shell.enqueue(.success(Self.shellResult(stdout: "origin\n")))
        await shell.enqueue(.success(Self.shellResult(stdout: "refs/remotes/origin/main\n")))
        await shell.enqueue(.success(Self.shellResult()))

        let service = CLIGitService(shell: shell)

        _ = try await service.commitsAheadOfBase(baseBranch: "main", remoteName: nil, in: "/tmp/project")
        _ = try await service.commitsAheadOfBaseDetails(baseBranch: "main", remoteName: nil, in: "/tmp/project")

        let invocations = await shell.invocations
        XCTAssertEqual(invocations[2].args, ["rev-list", "origin/main..HEAD", "--count"])
        XCTAssertEqual(invocations[5].args, ["log", "--pretty=format:%H%n%s%n%an%n%aI", "origin/main..HEAD"])
    }

    func testAheadCountAndDetailsUseSameRemoteCompareRef() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(Self.shellResult(stdout: "refs/remotes/origin/main\n")))
        await shell.enqueue(.success(Self.shellResult(stdout: "2\n")))
        await shell.enqueue(.success(Self.shellResult(stdout: "refs/remotes/origin/main\n")))
        await shell.enqueue(.success(Self.shellResult()))

        let service = CLIGitService(shell: shell)

        _ = try await service.commitsAheadOfBase(baseBranch: "main", remoteName: "origin", in: "/tmp/project")
        _ = try await service.commitsAheadOfBaseDetails(baseBranch: "main", remoteName: "origin", in: "/tmp/project")

        let invocations = await shell.invocations
        XCTAssertEqual(invocations[1].args, ["rev-list", "origin/main..HEAD", "--count"])
        XCTAssertEqual(invocations[3].args, ["log", "--pretty=format:%H%n%s%n%an%n%aI", "origin/main..HEAD"])
    }

    func testDiffForCommitRequestsFullPatchForCommit() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(Self.shellResult(stdout: "diff --git a/App.swift b/App.swift\n")))

        let service = CLIGitService(shell: shell)

        let diff = try await service.diffForCommit(hash: "abc123", in: "/tmp/project")

        XCTAssertEqual(diff, "diff --git a/App.swift b/App.swift\n")

        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.args, ["show", "--no-color", "--unified=2000", "--format=", "abc123"])
        XCTAssertEqual(invocation.stdoutLimitBytes, 30 * 1024 * 1024)
        XCTAssertEqual(invocation.stderrLimitBytes, 512 * 1024)
    }

    func testDiffForCommitThrowsWhenOutputIsTruncated() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(Self.shellResult(stdout: "truncated", stdoutWasTruncated: true)))

        let service = CLIGitService(shell: shell)

        do {
            _ = try await service.diffForCommit(hash: "abc123", in: "/tmp/project")
            XCTFail("Expected diffForCommit to throw")
        } catch GitError.outputTooLarge(let message) {
            XCTAssertEqual(message, "Commit diff output exceeded 30MB")
        }
    }
}

extension GitServiceTests {
    static func shellResult(
        stdout: String = "",
        stdoutData: Data? = nil,
        stderr: String = "",
        exitCode: Int32 = 0,
        stdoutWasTruncated: Bool = false,
        stderrWasTruncated: Bool = false
    ) -> ShellResult {
        ShellResult(
            stdout: stdout,
            stdoutData: stdoutData,
            stderr: stderr,
            exitCode: exitCode,
            stdoutWasTruncated: stdoutWasTruncated,
            stderrWasTruncated: stderrWasTruncated
        )
    }
}

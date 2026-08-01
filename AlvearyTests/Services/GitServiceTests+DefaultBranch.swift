import Foundation
import XCTest

@testable import Alveary

/// `CLIGitService.defaultBranch(remoteName:in:)` — the resolution that keeps the
/// commit list, the ahead counts, and the pull-request base off a persisted
/// `Project.baseRef` that was captured once at import and never re-detected.
extension GitServiceTests {
    func testDefaultBranchPrefersTheRecordedRemoteHead() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(Self.shellResult(stdout: "refs/remotes/origin/trunk\n")))
        let service = CLIGitService(shell: shell)

        let resolved = await service.defaultBranch(remoteName: "origin", in: "/tmp/project")

        XCTAssertEqual(resolved, "trunk")
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 1)
        XCTAssertEqual(invocations[0].args, ["symbolic-ref", "refs/remotes/origin/HEAD"])
    }

    /// A symbolic ref pointing outside the remote's namespace is not a default
    /// branch, so it must not be parsed into one.
    func testDefaultBranchIgnoresARemoteHeadOutsideTheRemoteNamespace() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(Self.shellResult(stdout: "refs/heads/main\n")))
        await shell.enqueue(.success(Self.shellResult(exitCode: 1)))
        await shell.enqueue(.success(Self.shellResult(exitCode: 1)))
        await shell.enqueue(.success(Self.shellResult(exitCode: 1)))
        await shell.enqueue(.success(Self.shellResult(exitCode: 1)))
        let service = CLIGitService(shell: shell)

        let resolved = await service.defaultBranch(remoteName: "origin", in: "/tmp/project")

        XCTAssertNil(resolved)
    }

    func testDefaultBranchProbesConventionalRemoteNamesWhenRemoteHeadIsMissing() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(Self.shellResult(exitCode: 1)))
        await shell.enqueue(.success(Self.shellResult()))
        let service = CLIGitService(shell: shell)

        let resolved = await service.defaultBranch(remoteName: "origin", in: "/tmp/project")

        XCTAssertEqual(resolved, "main")
        let invocations = await shell.invocations
        XCTAssertEqual(invocations[1].args, ["show-ref", "--verify", "--quiet", "refs/remotes/origin/main"])
    }

    func testDefaultBranchFallsBackToTheSecondConventionalNameWhenTheFirstIsAbsent() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(Self.shellResult(exitCode: 1)))
        await shell.enqueue(.success(Self.shellResult(exitCode: 1)))
        await shell.enqueue(.success(Self.shellResult()))
        let service = CLIGitService(shell: shell)

        let resolved = await service.defaultBranch(remoteName: "origin", in: "/tmp/project")

        XCTAssertEqual(resolved, "master")
        let invocations = await shell.invocations
        XCTAssertEqual(invocations[2].args, ["show-ref", "--verify", "--quiet", "refs/remotes/origin/master"])
    }

    func testDefaultBranchFallsBackToALocalConventionalBranchWithoutARemote() async {
        let shell = MockShellRunner()
        // `git remote` reports nothing, so no remote probes run at all.
        await shell.enqueue(.success(Self.shellResult()))
        await shell.enqueue(.success(Self.shellResult(exitCode: 1)))
        await shell.enqueue(.success(Self.shellResult()))
        let service = CLIGitService(shell: shell)

        let resolved = await service.defaultBranch(remoteName: nil, in: "/tmp/project")

        XCTAssertEqual(resolved, "master")
        let invocations = await shell.invocations
        XCTAssertEqual(invocations[0].args, ["remote"])
        XCTAssertEqual(invocations[1].args, ["show-ref", "--verify", "--quiet", "refs/heads/main"])
        XCTAssertEqual(invocations[2].args, ["show-ref", "--verify", "--quiet", "refs/heads/master"])
    }

    func testDefaultBranchIsNilWhenNothingResolves() async {
        let shell = MockShellRunner()
        for _ in 0..<3 {
            await shell.enqueue(.success(Self.shellResult(exitCode: 1)))
        }
        let service = CLIGitService(shell: shell)

        let resolved = await service.defaultBranch(remoteName: nil, in: "/tmp/project")

        XCTAssertNil(resolved)
    }

    /// The protocol carries a nil-returning default so stubs need no changes, so
    /// prove the CLI implementation is the witness. The modals hold a
    /// `GitService` existential, and if the default won there instead, the
    /// pull-request base would silently fall back to the persisted hint forever.
    func testDefaultBranchResolvesThroughTheGitServiceExistential() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(Self.shellResult(stdout: "refs/remotes/origin/trunk\n")))
        let service: GitService = CLIGitService(shell: shell)

        let resolved = await service.defaultBranch(remoteName: "origin", in: "/tmp/project")

        XCTAssertEqual(resolved, "trunk")
    }

    /// A repository with one non-`origin` remote still resolves against it.
    func testEffectiveRemoteNameUsesASoleNonOriginRemote() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(Self.shellResult(stdout: "upstream\n")))
        await shell.enqueue(.success(Self.shellResult(stdout: "refs/remotes/upstream/main\n")))
        let service = CLIGitService(shell: shell)

        let resolved = await service.defaultBranch(remoteName: nil, in: "/tmp/project")

        XCTAssertEqual(resolved, "main")
        let invocations = await shell.invocations
        XCTAssertEqual(invocations[1].args, ["symbolic-ref", "refs/remotes/upstream/HEAD"])
    }

    /// Several remotes and no way to tell which is authoritative: prefer
    /// `origin` rather than guessing.
    func testEffectiveRemoteNamePrefersOriginAmongSeveralRemotes() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(Self.shellResult(stdout: "fork\norigin\nupstream\n")))
        await shell.enqueue(.success(Self.shellResult(stdout: "refs/remotes/origin/main\n")))
        let service = CLIGitService(shell: shell)

        let resolved = await service.defaultBranch(remoteName: nil, in: "/tmp/project")

        XCTAssertEqual(resolved, "main")
        let invocations = await shell.invocations
        XCTAssertEqual(invocations[1].args, ["symbolic-ref", "refs/remotes/origin/HEAD"])
    }
}

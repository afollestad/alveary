import Foundation
import XCTest

@testable import Alveary

@MainActor
final class WorktreeManagerTests: XCTestCase {
    // Regression test for the case where the user cancels creation while `git worktree add` is
    // mid-run. Cancellation terminates git via SIGTERM, the add call fails, and the manager must
    // still clean up any partial worktree without deleting a branch whose ownership is unproven.
    func testCreateCleansUpWhenWorktreeAddFails() async throws {
        let projectURL = try makeTemporaryProject()
        let worktreesBaseURL = try makeTemporaryWorktreesBase()

        let shell = MockShellRunner()
        await shell.enqueue(.success(Self.failingShellResult()))
        await shell.enqueue(.success(Self.emptyShellResult()))
        await shell.enqueue(
            .success(
                ShellResult(
                    stdout: "",
                    stderr: "terminated",
                    exitCode: 143,
                    stdoutWasTruncated: false,
                    stderrWasTruncated: false
                )
            )
        )
        await shell.enqueue(
            .success(
                ShellResult(
                    stdout: "",
                    stderr: "fatal: 'X' is not a working tree",
                    exitCode: 128,
                    stdoutWasTruncated: false,
                    stderrWasTruncated: false
                )
            )
        )
        var settings = AppSettings()
        settings.worktreesBaseDirectory = worktreesBaseURL.path
        let manager = DefaultWorktreeManager(
            settingsService: InMemorySettingsService(current: settings),
            shell: shell
        )

        do {
            _ = try await manager.create(
                projectPath: projectURL.path,
                threadName: "Interrupted add",
                baseRef: "main",
                remoteName: "origin"
            )
            XCTFail("Expected create failure when `git worktree add` fails")
        } catch is GitError {
            // Expected
        }

        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 4, "Expected worktree cleanup without branch deletion after failed add")
        let cleanupInvocation = try XCTUnwrap(invocations.last)
        XCTAssertEqual(Array(cleanupInvocation.args.prefix(3)), ["worktree", "remove", "--force"])
        XCTAssertFalse(invocations.contains { Array($0.args.prefix(2)) == ["update-ref", "-d"] })
    }

    // Regression test for the "first empty folder, retry makes `-2`" bug: when `git worktree add`
    // was interrupted before git registered the worktree, `git worktree remove --force` fails with
    // "not a working tree" but the partial directory remains. The filesystem fallback must still
    // remove it so a subsequent create can reuse the original name.
    func testRemoveWorktreeDeletesDirectoryEvenWhenGitWorktreeRemoveFails() async throws {
        let projectURL = try makeTemporaryProject()
        let worktreesParentURL = projectURL.deletingLastPathComponent().appendingPathComponent("worktrees")
        let worktreeURL = worktreesParentURL.appendingPathComponent("leftover")
        try FileManager.default.createDirectory(at: worktreeURL, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: worktreesParentURL) }

        let shell = MockShellRunner()
        await shell.enqueue(
            .success(
                ShellResult(
                    stdout: "",
                    stderr: "fatal: '\(worktreeURL.path)' is not a working tree",
                    exitCode: 128,
                    stdoutWasTruncated: false,
                    stderrWasTruncated: false
                )
            )
        )

        let manager = DefaultWorktreeManager(settingsService: InMemorySettingsService(), shell: shell)

        _ = try await manager.removeWorktree(projectPath: projectURL.path, worktreePath: worktreeURL.path)

        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: worktreesParentURL.path))
    }

    func testRemoveRefusesMainRepositoryEvenWithTrailingSlash() async throws {
        let projectURL = try makeTemporaryProject()
        let listOutput = """
        worktree \(projectURL.path)
        HEAD \(WorktreeTestObjectID.main)
        branch refs/heads/main

        worktree \(projectURL.deletingLastPathComponent().appendingPathComponent("worktrees/demo").path)
        HEAD \(WorktreeTestObjectID.worktree)
        branch refs/heads/alveary/demo
        """

        let shell = MockShellRunner()
        await shell.enqueue(
            .success(
                ShellResult(
                    stdout: listOutput,
                    stderr: "",
                    exitCode: 0,
                    stdoutWasTruncated: false,
                    stderrWasTruncated: false
                )
            )
        )
        let manager = DefaultWorktreeManager(settingsService: InMemorySettingsService(), shell: shell)

        do {
            try await manager.remove(
                projectPath: projectURL.path,
                worktreePath: projectURL.path + "/",
                branch: "main"
            )
            XCTFail("Expected refusal to remove main repo")
        } catch let error as GitError {
            XCTAssertEqual(error, .commandFailed("Refusing to remove: \(projectURL.path)/ is not a removable worktree"))
        }
    }

    func testRemoveRunsTeardownScriptForWorktrees() async throws {
        let projectURL = try makeTemporaryProject()
        let worktreeURL = projectURL.deletingLastPathComponent().appendingPathComponent("worktrees/demo")
        try writeProjectConfig(
            at: projectURL,
            json: """
            {
              "scripts": {
                "teardown": "echo teardown"
              }
            }
            """
        )

        let shell = MockShellRunner()
        await shell.enqueue(
            .success(
                ShellResult(
                    stdout: worktreeListOutput(
                        projectPath: projectURL.path,
                        worktreePath: worktreeURL.path,
                        branch: "alveary/demo"
                    ),
                    stderr: "",
                    exitCode: 0,
                    stdoutWasTruncated: false,
                    stderrWasTruncated: false
                )
            )
        )

        let manager = DefaultWorktreeManager(settingsService: InMemorySettingsService(), shell: shell)

        try await manager.remove(
            projectPath: projectURL.path,
            worktreePath: worktreeURL.path,
            branch: "alveary/demo"
        )

        let invocations = await shell.invocations
        XCTAssertEqual(invocations[0].args, ["worktree", "list", "--porcelain"])
        XCTAssertEqual(invocations[1].executable, "/bin/sh")
        XCTAssertEqual(invocations[1].args, ["-c", "echo teardown"])
        XCTAssertEqual(invocations[1].directory, worktreeURL.path)
        XCTAssertEqual(invocations[1].timeout, .seconds(60))
        XCTAssertEqual(invocations[2].args, ["worktree", "remove", "--force", worktreeURL.path])
        XCTAssertEqual(invocations[3].args, ["update-ref", "-d", "--", "refs/heads/alveary/demo", WorktreeTestObjectID.worktree])
        assertLifecycleEnvironment(
            invocations[1].environment,
            threadName: "demo",
            branch: "alveary/demo",
            projectPath: projectURL.path,
            worktreePath: worktreeURL.path
        )
    }

    func testRemoveDeletesLeftoverWorktreeDirectoryButNotParent() async throws {
        let projectURL = try makeTemporaryProject()
        let worktreesParentURL = projectURL.deletingLastPathComponent().appendingPathComponent("worktrees")
        let worktreeURL = worktreesParentURL.appendingPathComponent("demo")
        try FileManager.default.createDirectory(at: worktreeURL, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: worktreesParentURL) }

        let shell = MockShellRunner()
        await shell.enqueue(
            .success(
                ShellResult(
                    stdout: worktreeListOutput(
                        projectPath: projectURL.path,
                        worktreePath: worktreeURL.path,
                        branch: "alveary/demo"
                    ),
                    stderr: "",
                    exitCode: 0,
                    stdoutWasTruncated: false,
                    stderrWasTruncated: false
                )
            )
        )
        await shell.enqueue(.success(Self.emptyShellResult()))
        await shell.enqueue(.success(Self.emptyShellResult()))
        await shell.enqueue(.success(Self.emptyShellResult()))

        let manager = DefaultWorktreeManager(settingsService: InMemorySettingsService(), shell: shell)

        try await manager.remove(
            projectPath: projectURL.path,
            worktreePath: worktreeURL.path,
            branch: "alveary/demo"
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: worktreesParentURL.path))
    }

    func testRemoveAllDeletesRegisteredWorktreesAndProjectNamespaceDirectory() async throws {
        let projectURL = try makeTemporaryProject()
        let worktreesBaseURL = projectURL.deletingLastPathComponent().appendingPathComponent("worktrees")
        let worktreeURL = worktreesBaseURL.appendingPathComponent("demo/worktree")
        let namespaceDirectory = namespacedWorktreesDirectory(for: projectURL, base: worktreesBaseURL)
        try FileManager.default.createDirectory(at: namespaceDirectory, withIntermediateDirectories: true)

        let listOutput = """
        worktree \(projectURL.path)
        HEAD \(WorktreeTestObjectID.main)
        branch refs/heads/main

        worktree \(worktreeURL.path)
        HEAD \(WorktreeTestObjectID.worktree)
        branch refs/heads/alveary/demo
        """

        let shell = MockShellRunner()
        await shell.enqueue(
            .success(
                ShellResult(
                    stdout: listOutput,
                    stderr: "",
                    exitCode: 0,
                    stdoutWasTruncated: false,
                    stderrWasTruncated: false
                )
            )
        )
        await shell.enqueue(.success(Self.emptyShellResult()))
        await shell.enqueue(.success(Self.emptyShellResult()))
        await shell.enqueue(.success(Self.emptyShellResult()))

        var settings = AppSettings()
        settings.worktreesBaseDirectory = worktreesBaseURL.path
        let manager = DefaultWorktreeManager(
            settingsService: InMemorySettingsService(current: settings),
            shell: shell
        )

        try await manager.removeAll(projectPath: projectURL.path)

        let invocations = await shell.invocations
        XCTAssertEqual(invocations.map(\.args), [
            ["worktree", "list", "--porcelain"],
            ["worktree", "remove", "--force", worktreeURL.path],
            ["update-ref", "-d", "--", "refs/heads/alveary/demo", WorktreeTestObjectID.worktree]
        ])
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: namespaceDirectory.path))
    }

    func testRemoveAllRemovesNamespacedWorktreesWhenProjectFolderIsAlreadyGone() async throws {
        let parentURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let missingProjectURL = parentURL.appendingPathComponent("missing-project")
        let worktreesBaseURL = parentURL.appendingPathComponent("worktrees")
        let namespaceDirectory = namespacedWorktreesDirectory(for: missingProjectURL, base: worktreesBaseURL)

        try FileManager.default.createDirectory(at: namespaceDirectory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: parentURL) }

        let shell = MockShellRunner()
        var settings = AppSettings()
        settings.worktreesBaseDirectory = worktreesBaseURL.path
        let manager = DefaultWorktreeManager(
            settingsService: InMemorySettingsService(current: settings),
            shell: shell
        )

        try await manager.removeAll(projectPath: missingProjectURL.path)

        let invocations = await shell.invocations
        XCTAssertTrue(invocations.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingProjectURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: namespaceDirectory.path))
    }

}

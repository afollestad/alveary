import Foundation
import XCTest

@testable import Alveary

@MainActor
extension WorktreeManagerTests {
    func testValidateCreationChecksTheResolvedRemoteBaseCommit() async throws {
        let worktreesBaseURL = try makeTemporaryWorktreesBase()
        let shell = MockShellRunner()
        await shell.enqueue(.success(Self.emptyShellResult()))
        await shell.enqueue(.success(Self.emptyShellResult()))
        await shell.enqueue(.success(Self.emptyShellResult()))
        var settings = AppSettings()
        settings.worktreesBaseDirectory = worktreesBaseURL.path
        let manager = DefaultWorktreeManager(
            settingsService: InMemorySettingsService(current: settings),
            shell: shell
        )

        try await manager.validateCreation(
            projectPath: "/tmp/project",
            baseRef: "main",
            remoteName: "upstream"
        )

        let invocations = await shell.invocations
        XCTAssertEqual(invocations.map(\.args), [
            ["check-ref-format", "--branch", "alveary/scheduled-task-validation"],
            ["fetch", "upstream", "main"],
            ["rev-parse", "--verify", "upstream/main^{commit}"]
        ])
    }

    func testValidateCreationRejectsAConfiguredWorktreesPathThatIsAFile() async throws {
        let parentURL = try makeTemporaryProject()
        let worktreesFileURL = parentURL.appendingPathComponent("worktrees-file")
        try Data().write(to: worktreesFileURL)
        var settings = AppSettings()
        settings.worktreesBaseDirectory = worktreesFileURL.path
        let shell = MockShellRunner()
        let manager = DefaultWorktreeManager(
            settingsService: InMemorySettingsService(current: settings),
            shell: shell
        )

        do {
            try await manager.validateCreation(
                projectPath: "/tmp/project",
                baseRef: "main",
                remoteName: nil
            )
            XCTFail("Expected a non-directory worktrees path to be rejected")
        } catch let error as GitError {
            XCTAssertEqual(
                error,
                .commandFailed("The configured worktrees path is not a directory: \(worktreesFileURL.path)")
            )
        }

        let invocations = await shell.invocations
        XCTAssertTrue(invocations.isEmpty)
    }

    func testValidateCreationRejectsADanglingConfiguredWorktreesSymlink() async throws {
        let parentURL = try makeTemporaryProject()
        let worktreesLinkURL = parentURL.appendingPathComponent("worktrees-link")
        let missingTargetURL = parentURL.appendingPathComponent("missing-target")
        try FileManager.default.createSymbolicLink(
            at: worktreesLinkURL,
            withDestinationURL: missingTargetURL
        )
        var settings = AppSettings()
        settings.worktreesBaseDirectory = worktreesLinkURL.path
        let shell = MockShellRunner()
        let manager = DefaultWorktreeManager(
            settingsService: InMemorySettingsService(current: settings),
            shell: shell
        )

        do {
            try await manager.validateCreation(
                projectPath: "/tmp/project",
                baseRef: "main",
                remoteName: nil
            )
            XCTFail("Expected a dangling worktrees symlink to be rejected")
        } catch let error as GitError {
            XCTAssertEqual(
                error,
                .commandFailed("The configured worktrees path is not a directory: \(worktreesLinkURL.path)")
            )
        }

        let invocations = await shell.invocations
        XCTAssertTrue(invocations.isEmpty)
    }

    func testValidateCreationRejectsAnExistingConfiguredWorktreesSymlink() async throws {
        let parentURL = try makeTemporaryProject()
        let worktreesTargetURL = parentURL.appendingPathComponent("worktrees-target", isDirectory: true)
        let worktreesLinkURL = parentURL.appendingPathComponent("worktrees-link", isDirectory: true)
        try FileManager.default.createDirectory(at: worktreesTargetURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: worktreesLinkURL,
            withDestinationURL: worktreesTargetURL
        )
        var settings = AppSettings()
        settings.worktreesBaseDirectory = worktreesLinkURL.path
        let shell = MockShellRunner()
        let manager = DefaultWorktreeManager(
            settingsService: InMemorySettingsService(current: settings),
            shell: shell
        )

        do {
            try await manager.validateCreation(
                projectPath: parentURL.path,
                baseRef: nil,
                remoteName: nil
            )
            XCTFail("Expected an existing worktrees symlink to be rejected")
        } catch let error as GitError {
            XCTAssertEqual(
                error,
                .commandFailed("The configured worktrees path is not a directory: \(worktreesLinkURL.path)")
            )
        }

        let invocations = await shell.invocations
        XCTAssertTrue(invocations.isEmpty)
    }

    func testValidateCreationRejectsAConfiguredWorktreesPathWithASymlinkedAncestor() async throws {
        let root = try makeTemporaryProject()
        let realParentURL = root.appendingPathComponent("real-parent", isDirectory: true)
        let parentLinkURL = root.appendingPathComponent("parent-link", isDirectory: true)
        let worktreesBaseURL = parentLinkURL.appendingPathComponent("Worktrees", isDirectory: true)
        try FileManager.default.createDirectory(
            at: realParentURL.appendingPathComponent("Worktrees", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: parentLinkURL,
            withDestinationURL: realParentURL
        )
        var settings = AppSettings()
        settings.worktreesBaseDirectory = worktreesBaseURL.path
        let shell = MockShellRunner()
        let manager = DefaultWorktreeManager(
            settingsService: InMemorySettingsService(current: settings),
            shell: shell
        )

        do {
            try await manager.validateCreation(
                projectPath: "/tmp/project",
                baseRef: nil,
                remoteName: nil
            )
            XCTFail("Expected a symlinked worktrees ancestor to be rejected")
        } catch let error as GitError {
            XCTAssertEqual(
                error,
                .commandFailed("The configured worktrees path is not a directory: \(worktreesBaseURL.path)")
            )
        }

        let invocations = await shell.invocations
        XCTAssertTrue(invocations.isEmpty)
    }

    func testValidateCreationRejectsANoncanonicalConfiguredWorktreesPath() async throws {
        let root = try makeTemporaryProject()
        let worktreesBase = "\(root.path)/unused/../Worktrees"
        var settings = AppSettings()
        settings.worktreesBaseDirectory = worktreesBase
        let shell = MockShellRunner()
        let manager = DefaultWorktreeManager(
            settingsService: InMemorySettingsService(current: settings),
            shell: shell
        )

        do {
            try await manager.validateCreation(
                projectPath: "/tmp/project",
                baseRef: nil,
                remoteName: nil
            )
            XCTFail("Expected a noncanonical worktrees path to be rejected")
        } catch let error as GitError {
            XCTAssertEqual(
                error,
                .commandFailed("The configured worktrees path is not a directory: \(worktreesBase)")
            )
        }

        let invocations = await shell.invocations
        XCTAssertTrue(invocations.isEmpty)
    }

    func testIdentityAwareCreateRechecksDestinationAfterPreflight() async throws {
        let root = try makeTemporaryProject()
        let projectURL = root.appendingPathComponent("Project", isDirectory: true)
        let worktreesBaseURL = root.appendingPathComponent("Worktrees", isDirectory: true)
        let movedWorktreesBaseURL = root.appendingPathComponent("MovedWorktrees", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreesBaseURL, withIntermediateDirectories: true)
        let ownershipService = DefaultTaskWorkspaceOwnershipService(
            privateWorkspacesRoot: root.appendingPathComponent("Private", isDirectory: true),
            worktreeOwnershipRecordsRoot: root.appendingPathComponent("Records", isDirectory: true)
        )
        let sourceIdentity = try ownershipService.directoryIdentity(at: projectURL.path)
        var settings = AppSettings()
        settings.worktreesBaseDirectory = worktreesBaseURL.path
        let shell = MockShellRunner()
        let manager = DefaultWorktreeManager(
            settingsService: InMemorySettingsService(current: settings),
            shell: shell
        )
        try await manager.validateCreation(
            projectPath: projectURL.path,
            baseRef: nil,
            remoteName: nil,
            expectedProjectIdentity: sourceIdentity
        )
        try FileManager.default.moveItem(at: worktreesBaseURL, to: movedWorktreesBaseURL)
        try FileManager.default.createSymbolicLink(
            at: worktreesBaseURL,
            withDestinationURL: movedWorktreesBaseURL
        )

        do {
            _ = try await manager.create(
                projectPath: projectURL.path,
                threadName: "Destination race",
                baseRef: nil,
                remoteName: nil,
                expectedProjectIdentity: sourceIdentity
            )
            XCTFail("Expected creation to reject the replaced destination")
        } catch let error as GitError {
            XCTAssertEqual(
                error,
                .commandFailed("The configured worktrees path is not a directory: \(worktreesBaseURL.path)")
            )
        }

        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 2)
    }

    func testValidateCreationRejectsAnInvalidBranchPrefixBeforeResolvingTheBase() async throws {
        let worktreesBaseURL = try makeTemporaryWorktreesBase()
        let shell = MockShellRunner()
        await shell.enqueue(.success(ShellResult(
            stdout: "",
            stderr: "fatal: invalid branch name",
            exitCode: 1,
            stdoutWasTruncated: false,
            stderrWasTruncated: false
        )))
        var settings = AppSettings()
        settings.branchPrefix = "invalid prefix/"
        settings.worktreesBaseDirectory = worktreesBaseURL.path
        let manager = DefaultWorktreeManager(
            settingsService: InMemorySettingsService(current: settings),
            shell: shell
        )

        do {
            try await manager.validateCreation(
                projectPath: "/tmp/project",
                baseRef: "main",
                remoteName: "upstream"
            )
            XCTFail("Expected an invalid branch prefix to be rejected")
        } catch let error as GitError {
            XCTAssertEqual(error, .commandFailed("fatal: invalid branch name"))
        }

        let invocations = await shell.invocations
        XCTAssertEqual(
            invocations.map(\.args),
            [["check-ref-format", "--branch", "invalid prefix/scheduled-task-validation"]]
        )
    }

    func testAtomicBranchDeleteAcceptsFullSHA256ObjectID() async throws {
        let shell = MockShellRunner()
        let manager = DefaultWorktreeManager(
            settingsService: InMemorySettingsService(),
            shell: shell
        )

        try await manager.deleteBranch(
            projectPath: "/tmp/project",
            branch: "alveary/owned",
            expectedOID: WorktreeTestObjectID.sha256
        )

        let invocations = await shell.invocations
        XCTAssertEqual(
            invocations.map(\.args),
            [["update-ref", "-d", "--", "refs/heads/alveary/owned", WorktreeTestObjectID.sha256]]
        )
    }

    func testAtomicBranchDeleteRejectsInvalidObjectIDWithoutInvokingGit() async {
        await assertBranchDeletionRejectsObjectID(String(repeating: "g", count: 40))
    }

    func testAtomicBranchDeleteRejectsOptionShapedObjectIDWithoutInvokingGit() async {
        await assertBranchDeletionRejectsObjectID("--" + String(repeating: "a", count: 38))
    }

    func testAtomicBranchDeleteRejectsAllZeroObjectIDsWithoutInvokingGit() async {
        await assertBranchDeletionRejectsObjectID(String(repeating: "0", count: 40))
        await assertBranchDeletionRejectsObjectID(String(repeating: "0", count: 64))
    }

    private func assertBranchDeletionRejectsObjectID(
        _ objectID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let shell = MockShellRunner()
        let manager = DefaultWorktreeManager(
            settingsService: InMemorySettingsService(),
            shell: shell
        )
        let caughtError: Error?
        do {
            try await manager.deleteBranch(
                projectPath: "/tmp/project",
                branch: "alveary/owned",
                expectedOID: objectID
            )
            caughtError = nil
        } catch {
            caughtError = error
        }

        XCTAssertEqual(
            caughtError as? GitError,
            .commandFailed("Refusing to delete branch alveary/owned because its expected object ID is invalid"),
            file: file,
            line: line
        )
        let invocations = await shell.invocations
        XCTAssertTrue(invocations.isEmpty, file: file, line: line)
    }
}

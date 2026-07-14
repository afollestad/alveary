import Foundation
import XCTest

@testable import Alveary

@MainActor
extension WorktreeManagerTests {
    func testAtomicBranchDeleteRemovesMatchingRef() async throws {
        let shell = BranchRefRaceShell(mode: .directMatching)
        let manager = DefaultWorktreeManager(
            settingsService: InMemorySettingsService(),
            shell: shell
        )

        try await manager.deleteBranch(
            projectPath: "/tmp/project",
            branch: "alveary/owned",
            expectedOID: WorktreeTestObjectID.owned
        )

        let branchOID = await shell.branchOID()
        let invocations = await shell.invocations()
        XCTAssertNil(branchOID)
        XCTAssertEqual(
            invocations.first?.args,
            ["update-ref", "-d", "--", "refs/heads/alveary/owned", WorktreeTestObjectID.owned]
        )
    }

    func testAtomicBranchDeletePreservesRetargetedRef() async throws {
        let shell = BranchRefRaceShell(mode: .directRetarget)
        let manager = DefaultWorktreeManager(
            settingsService: InMemorySettingsService(),
            shell: shell
        )

        for _ in 0..<2 {
            do {
                try await manager.deleteBranch(
                    projectPath: "/tmp/project",
                    branch: "alveary/owned",
                    expectedOID: WorktreeTestObjectID.owned
                )
                XCTFail("Expected the retargeted ref to be preserved")
            } catch let error as GitError {
                XCTAssertEqual(error, .commandFailed("Refusing to delete branch alveary/owned because its ref changed"))
            }
        }

        let branchOID = await shell.branchOID()
        let invocations = await shell.invocations()
        XCTAssertEqual(branchOID, WorktreeTestObjectID.replacement)
        XCTAssertEqual(invocations.filter { $0.args.starts(with: ["update-ref", "-d"]) }.count, 2)
    }

    func testAtomicBranchDeleteFailureWithMatchingRefIsRetryable() async {
        await assertAtomicBranchDeletion(.failedDeleteRefUnchanged, expected: .retryableGit(.commandFailed("delete failed")))
    }

    func testAtomicBranchDeleteFailureSucceedsWhenRefIsAbsent() async {
        await assertAtomicBranchDeletion(.failedDeleteRefAbsent, expected: .success)
    }

    func testAtomicBranchDeleteLookupThrowIsNotRetryable() async {
        await assertAtomicBranchDeletion(.failedDeleteLookupThrows, expected: .shellFailure(.lookupFailed))
    }

    func testAtomicBranchDeleteLookupFailureIsNotRetryable() async {
        await assertAtomicBranchDeletion(.failedDeleteLookupInvalidExit, expected: .gitFailure(.commandFailed("lookup failed")))
    }

    func testAtomicBranchDeleteEmptyLookupOIDIsNotRetryable() async {
        let error = GitError.commandFailed("Git returned an empty object ID for branch alveary/owned")
        await assertAtomicBranchDeletion(.failedDeleteLookupEmptyOID, expected: .gitFailure(error))
    }

    func testOrdinaryRemovePreservesBranchRetargetedAfterWorktreeProof() async throws {
        let fixture = try BranchRefRemovalFixture(mode: .removeRetarget)
        defer { fixture.removeFiles() }

        do {
            try await fixture.manager.remove(
                projectPath: fixture.project.path,
                worktreePath: fixture.worktree.path,
                branch: "alveary/owned"
            )
            XCTFail("Expected the retargeted ref to be preserved")
        } catch let error as GitError {
            XCTAssertEqual(error, .commandFailed("Refusing to delete branch alveary/owned because its ref changed"))
        }

        let branchOID = await fixture.shell.branchOID()
        XCTAssertEqual(branchOID, WorktreeTestObjectID.replacement)
    }

    func testProjectCleanupPreservesBranchRetargetedAfterWorktreeProof() async throws {
        let fixture = try BranchRefRemovalFixture(mode: .removeRetarget)
        defer { fixture.removeFiles() }

        do {
            try await fixture.manager.removeAll(projectPath: fixture.project.path)
            XCTFail("Expected the retargeted ref to be preserved")
        } catch let error as GitError {
            XCTAssertEqual(error, .commandFailed("Refusing to delete branch alveary/owned because its ref changed"))
        }

        let branchOID = await fixture.shell.branchOID()
        XCTAssertEqual(branchOID, WorktreeTestObjectID.replacement)
    }

    func testCreationRollbackPreservesBranchRetargetedAfterFinalProof() async throws {
        let fixture = try BranchRefRemovalFixture(mode: .rollbackRetarget)
        defer { fixture.removeFiles() }
        try "{\"scripts\":{\"setup\":\"exit 1\"}}".write(
            to: fixture.project.appendingPathComponent(".alveary.json"),
            atomically: true,
            encoding: .utf8
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.manager.create(
                projectPath: fixture.project.path,
                threadName: "Rollback ref race",
                baseRef: nil,
                remoteName: nil
            )
        }

        let branchOID = await fixture.shell.branchOID()
        XCTAssertEqual(branchOID, WorktreeTestObjectID.replacement)
    }

    func testIdentityAwareRemoveRejectsSourceReplacementAfterInspection() async throws {
        let fixture = try WorktreeSourceIdentityFixture(mode: .worktreeList)
        defer { fixture.removeFiles() }

        do {
            try await fixture.manager.remove(
                projectPath: fixture.source.path,
                worktreePath: fixture.worktree.path,
                branch: "alveary/identity-race",
                expectedProjectIdentity: fixture.sourceIdentity,
                expectedWorktreeIdentity: fixture.worktreeIdentity
            )
            XCTFail("Expected the replaced source Project to be rejected")
        } catch let error as WorktreeSourceValidationError {
            XCTAssertEqual(error, .sourceProjectChanged(fixture.source.path))
        }

        let invocationCount = await fixture.shell.invocationCount()
        XCTAssertEqual(invocationCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.replacementSentinel.path))
    }

    func testIdentityAwareBranchDeleteRejectsSourceReplacementAfterInspection() async throws {
        let fixture = try WorktreeSourceIdentityFixture(mode: .branchLookup)
        defer { fixture.removeFiles() }

        do {
            try await fixture.manager.deleteBranch(
                projectPath: fixture.source.path,
                branch: "alveary/identity-race",
                expectedOID: WorktreeTestObjectID.expected,
                expectedProjectIdentity: fixture.sourceIdentity
            )
            XCTFail("Expected the replaced source Project to be rejected")
        } catch let error as WorktreeSourceValidationError {
            XCTAssertEqual(error, .sourceProjectChanged(fixture.source.path))
        }

        let invocationCount = await fixture.shell.invocationCount()
        XCTAssertEqual(invocationCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.replacementSentinel.path))
    }

    func testIdentityAwareRemovePreservesWorktreeReplacementBeforeFallbackDeletion() async throws {
        let fixture = try WorktreeSourceIdentityFixture(mode: .worktreeReplacementDuringRemoval)
        defer { fixture.removeFiles() }

        do {
            try await fixture.manager.remove(
                projectPath: fixture.source.path,
                worktreePath: fixture.worktree.path,
                branch: "alveary/identity-race",
                expectedProjectIdentity: fixture.sourceIdentity,
                expectedWorktreeIdentity: fixture.worktreeIdentity
            )
            XCTFail("Expected the replaced owned worktree to be preserved")
        } catch let error as WorktreeSourceValidationError {
            XCTAssertEqual(error, .ownedWorktreeChanged(fixture.worktree.path))
        }

        let invocationCount = await fixture.shell.invocationCount()
        XCTAssertEqual(invocationCount, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.worktreeReplacementSentinel.path))
    }

    func testIdentityAwareRemoveRejectsSourceReplacementDuringTeardownConfigLoad() async throws {
        let fixture = try WorktreeSourceIdentityFixture(mode: .sourceReplacementDuringTeardownConfig)
        defer { fixture.removeFiles() }

        do {
            try await fixture.manager.remove(
                projectPath: fixture.source.path,
                worktreePath: fixture.worktree.path,
                branch: "alveary/identity-race",
                expectedProjectIdentity: fixture.sourceIdentity,
                expectedWorktreeIdentity: fixture.worktreeIdentity
            )
            XCTFail("Expected the source replacement during teardown config loading to be rejected")
        } catch let error as WorktreeSourceValidationError {
            XCTAssertEqual(error, .sourceProjectChanged(fixture.source.path))
        }

        let invocationCount = await fixture.shell.invocationCount()
        XCTAssertEqual(invocationCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.replacementSentinel.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.worktree.path))
    }

    func testIdentityAwareRemoveRejectsWorktreeReplacementDuringTeardownScript() async throws {
        let fixture = try WorktreeSourceIdentityFixture(mode: .worktreeReplacementDuringTeardownScript)
        defer { fixture.removeFiles() }

        do {
            try await fixture.manager.remove(
                projectPath: fixture.source.path,
                worktreePath: fixture.worktree.path,
                branch: "alveary/identity-race",
                expectedProjectIdentity: fixture.sourceIdentity,
                expectedWorktreeIdentity: fixture.worktreeIdentity
            )
            XCTFail("Expected the worktree replacement during teardown to be rejected")
        } catch let error as WorktreeSourceValidationError {
            XCTAssertEqual(error, .ownedWorktreeChanged(fixture.worktree.path))
        }

        let invocationCount = await fixture.shell.invocationCount()
        XCTAssertEqual(invocationCount, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.worktreeReplacementSentinel.path))
    }

    func testIdentityAwareBranchDeleteRejectsSourceReplacementDuringDeletion() async throws {
        let fixture = try WorktreeSourceIdentityFixture(mode: .sourceReplacementDuringBranchDelete)
        defer { fixture.removeFiles() }

        do {
            try await fixture.manager.deleteBranch(
                projectPath: fixture.source.path,
                branch: "alveary/identity-race",
                expectedOID: WorktreeTestObjectID.expected,
                expectedProjectIdentity: fixture.sourceIdentity
            )
            XCTFail("Expected the source replacement during branch deletion to be rejected")
        } catch let error as WorktreeSourceValidationError {
            XCTAssertEqual(error, .sourceProjectChanged(fixture.source.path))
        }

        let invocationCount = await fixture.shell.invocationCount()
        XCTAssertEqual(invocationCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.replacementSentinel.path))
    }

    func testIdentityAwareRemoveKeepsTeardownCommandFailuresBestEffort() async throws {
        let fixture = try WorktreeSourceIdentityFixture(mode: .teardownCommandFailure)
        defer { fixture.removeFiles() }

        try await fixture.manager.remove(
            projectPath: fixture.source.path,
            worktreePath: fixture.worktree.path,
            branch: "alveary/identity-race",
            expectedProjectIdentity: fixture.sourceIdentity,
            expectedWorktreeIdentity: fixture.worktreeIdentity
        )

        let invocationCount = await fixture.shell.invocationCount()
        XCTAssertEqual(invocationCount, 4)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.worktree.path))
    }

}

@MainActor
private struct WorktreeSourceIdentityFixture {
    let root: URL
    let source: URL
    let worktree: URL
    let replacementSentinel: URL
    let worktreeReplacementSentinel: URL
    let sourceIdentity: TaskWorkspaceFileSystemIdentity
    let worktreeIdentity: TaskWorkspaceFileSystemIdentity
    let shell: IdentitySwappingWorktreeShell
    let manager: DefaultWorktreeManager

    init(mode: IdentitySwappingWorktreeShell.Mode) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorktreeSourceIdentityFixture-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let movedSource = root.appendingPathComponent("MovedSource", isDirectory: true)
        let worktree = root.appendingPathComponent("Worktree", isDirectory: true)
        let movedWorktree = root.appendingPathComponent("MovedWorktree", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        let ownership = DefaultTaskWorkspaceOwnershipService(
            privateWorkspacesRoot: root.appendingPathComponent("Private", isDirectory: true),
            worktreeOwnershipRecordsRoot: root.appendingPathComponent("Records", isDirectory: true)
        )
        let shell = IdentitySwappingWorktreeShell(
            mode: mode,
            source: source,
            movedSource: movedSource,
            worktree: worktree,
            movedWorktree: movedWorktree
        )
        self.root = root
        self.source = source
        self.worktree = worktree
        self.replacementSentinel = source.appendingPathComponent("keep.txt")
        self.worktreeReplacementSentinel = worktree.appendingPathComponent("keep.txt")
        self.sourceIdentity = try ownership.directoryIdentity(at: source.path)
        self.worktreeIdentity = try ownership.directoryIdentity(at: worktree.path)
        self.shell = shell
        self.manager = DefaultWorktreeManager(
            settingsService: InMemorySettingsService(current: AppSettings()),
            shell: shell,
            projectConfigLoader: { projectPath in
                if mode == .sourceReplacementDuringTeardownConfig {
                    try? FileManager.default.moveItem(at: source, to: movedSource)
                    try? FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
                    try? Data("keep".utf8).write(to: source.appendingPathComponent("keep.txt"))
                }
                if mode == .sourceReplacementDuringTeardownConfig ||
                    mode == .worktreeReplacementDuringTeardownScript ||
                    mode == .teardownCommandFailure {
                    return AlvearyProjectConfig(teardownScript: "echo teardown")
                }
                return await AlvearyProjectConfig(projectPath: projectPath)
            }
        )
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: root)
    }
}

private actor IdentitySwappingWorktreeShell: ShellRunner {
    enum Mode: Sendable, Equatable {
        case worktreeList
        case branchLookup
        case worktreeReplacementDuringRemoval
        case sourceReplacementDuringTeardownConfig
        case worktreeReplacementDuringTeardownScript
        case sourceReplacementDuringBranchDelete
        case teardownCommandFailure
    }

    private let mode: Mode
    private let source: URL
    private let movedSource: URL
    private let worktree: URL
    private let movedWorktree: URL
    private var calls = 0

    init(mode: Mode, source: URL, movedSource: URL, worktree: URL, movedWorktree: URL) {
        self.mode = mode
        self.source = source
        self.movedSource = movedSource
        self.worktree = worktree
        self.movedWorktree = movedWorktree
    }

    func run(
        executable: String,
        args: [String],
        in directory: String?,
        options: ShellRunOptions
    ) async throws -> ShellResult {
        calls += 1
        if calls == 1, mode == .worktreeList || mode == .branchLookup {
            try replaceSource()
        }
        if mode == .sourceReplacementDuringBranchDelete,
           args.starts(with: ["update-ref", "-d"]) {
            try replaceSource()
        }
        if mode == .worktreeReplacementDuringTeardownScript,
           executable == "/bin/sh" {
            try replaceWorktree()
        }
        if mode == .teardownCommandFailure,
           executable == "/bin/sh" {
            throw IdentitySwappingWorktreeShellError.intentionalTeardownFailure
        }
        if mode == .worktreeReplacementDuringRemoval,
           args.starts(with: ["worktree", "remove"]) {
            try replaceWorktree()
            return ShellResult(
                stdout: "",
                stderr: "worktree removal failed",
                exitCode: 1,
                stdoutWasTruncated: false,
                stderrWasTruncated: false
            )
        }
        let stdout: String
        switch mode {
        case .worktreeList,
             .worktreeReplacementDuringRemoval,
             .sourceReplacementDuringTeardownConfig,
             .worktreeReplacementDuringTeardownScript,
             .teardownCommandFailure:
            stdout = "worktree \(worktree.path)\nHEAD \(WorktreeTestObjectID.expected)\nbranch refs/heads/alveary/identity-race\n\n"
        case .branchLookup, .sourceReplacementDuringBranchDelete:
            stdout = "\(WorktreeTestObjectID.expected)\n"
        }
        return ShellResult(
            stdout: stdout,
            stderr: "",
            exitCode: 0,
            stdoutWasTruncated: false,
            stderrWasTruncated: false
        )
    }

    func invocationCount() -> Int {
        calls
    }

    private func replaceSource() throws {
        try FileManager.default.moveItem(at: source, to: movedSource)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: source.appendingPathComponent("keep.txt"))
    }

    private func replaceWorktree() throws {
        try FileManager.default.moveItem(at: worktree, to: movedWorktree)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: worktree.appendingPathComponent("keep.txt"))
    }
}

private enum IdentitySwappingWorktreeShellError: Error {
    case intentionalTeardownFailure
}

@MainActor
private struct BranchRefRemovalFixture {
    let root: URL
    let project: URL
    let worktree: URL
    let shell: BranchRefRaceShell
    let manager: DefaultWorktreeManager

    init(mode: BranchRefRaceShell.Mode) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BranchRefRemovalFixture-\(UUID().uuidString)", isDirectory: true)
        project = root.appendingPathComponent("Project", isDirectory: true)
        worktree = root.appendingPathComponent("Worktree", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        if mode == .removeRetarget {
            try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        }
        shell = BranchRefRaceShell(
            mode: mode,
            projectPath: project.path,
            worktreePath: worktree.path
        )
        var settings = AppSettings()
        settings.worktreesBaseDirectory = root.appendingPathComponent("ManagedWorktrees", isDirectory: true).path
        manager = DefaultWorktreeManager(
            settingsService: InMemorySettingsService(current: settings),
            shell: shell
        )
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: root)
    }
}

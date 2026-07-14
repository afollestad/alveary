import Foundation
import XCTest

@testable import Alveary

@MainActor
extension WorktreeManagerTests {
    func testIdentityAwareCreateRejectsSourceReplacementAfterTargetLookup() async throws {
        let fixture = try WorktreeCreationIdentityFixture(mode: .replaceSourceAfterTargetLookup)
        defer { fixture.removeFiles() }

        do {
            _ = try await fixture.manager.create(
                projectPath: fixture.source.path,
                threadName: "Identity race",
                baseRef: nil,
                remoteName: nil,
                expectedProjectIdentity: fixture.sourceIdentity
            )
            XCTFail("Expected the replaced source Project to be rejected")
        } catch let error as WorktreeSourceValidationError {
            XCTAssertEqual(error, .sourceProjectChanged(fixture.source.path))
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.sourceReplacementSentinel.path))
        let invocations = await fixture.shell.invocations()
        XCTAssertEqual(invocations.count, 2)
        XCTAssertEqual(invocations[0].args, ["check-ref-format", "--branch", "alveary/scheduled-task-validation"])
        XCTAssertEqual(Array(invocations[1].args.prefix(3)), ["show-ref", "--verify", "--quiet"])
        XCTAssertTrue(invocations[1].args[3].hasPrefix("refs/heads/alveary/identity-race-"))
    }

    func testIdentityAwareCreatePreservesSourceReplacementDuringSetup() async throws {
        let fixture = try WorktreeCreationIdentityFixture(mode: .replaceSourceDuringSetup)
        defer { fixture.removeFiles() }

        let rollbackError = try await fixture.assertRollbackError()

        XCTAssertEqual(rollbackError.cleanup.sourceProjectIdentity, fixture.sourceIdentity)
        XCTAssertNotNil(rollbackError.cleanup.worktreeIdentity)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.sourceReplacementSentinel.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rollbackError.cleanup.worktreePath))
        let invocations = await fixture.shell.invocations()
        XCTAssertFalse(invocations.contains { $0.args.starts(with: ["worktree", "remove"]) })
        XCTAssertFalse(invocations.contains { $0.args.starts(with: ["update-ref", "-d"]) })
        XCTAssertFalse(invocations.contains { $0.executable == "/bin/chmod" })
    }

    func testIdentityAwareCreatePreservesWorktreeReplacementDuringSetup() async throws {
        let fixture = try WorktreeCreationIdentityFixture(mode: .replaceWorktreeDuringSetup)
        defer { fixture.removeFiles() }

        let rollbackError = try await fixture.assertRollbackError()

        let expectedIdentity = try XCTUnwrap(rollbackError.cleanup.worktreeIdentity)
        XCTAssertNotEqual(
            try fixture.ownershipService.directoryIdentity(at: rollbackError.cleanup.worktreePath),
            expectedIdentity
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: URL(fileURLWithPath: rollbackError.cleanup.worktreePath)
                    .appendingPathComponent("keep.txt")
                    .path
            )
        )
        let invocations = await fixture.shell.invocations()
        XCTAssertFalse(invocations.contains { $0.args.starts(with: ["worktree", "remove"]) })
        XCTAssertFalse(invocations.contains { $0.executable == "/bin/chmod" })
    }

    func testIdentityAwareCreatePreservesWorktreeReplacementBeforeAddReturns() async throws {
        let fixture = try WorktreeCreationIdentityFixture(mode: .replaceWorktreeBeforeAddReturns)
        defer { fixture.removeFiles() }

        let rollbackError = try await fixture.assertRollbackError()

        let expectedIdentity = try XCTUnwrap(rollbackError.cleanup.worktreeIdentity)
        XCTAssertNotEqual(
            try fixture.ownershipService.directoryIdentity(at: rollbackError.cleanup.worktreePath),
            expectedIdentity
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: URL(fileURLWithPath: rollbackError.cleanup.worktreePath)
                    .appendingPathComponent("keep.txt")
                    .path
            )
        )
        let invocations = await fixture.shell.invocations()
        XCTAssertFalse(invocations.contains { $0.args.starts(with: ["worktree", "remove"]) })
        XCTAssertFalse(invocations.contains { $0.executable == "/bin/chmod" })
    }

    func testIdentityAwareCreateCleansPrecreatedTargetWhenAddIsCancelled() async throws {
        let fixture = try WorktreeCreationIdentityFixture(mode: .cancelDuringAdd)
        defer { fixture.removeFiles() }

        do {
            _ = try await fixture.manager.create(
                projectPath: fixture.source.path,
                threadName: "Identity race",
                baseRef: nil,
                remoteName: nil,
                expectedProjectIdentity: fixture.sourceIdentity
            )
            XCTFail("Expected worktree creation to be cancelled")
        } catch is CancellationError {
            // Expected.
        }

        let invocations = await fixture.shell.invocations()
        let addInvocation = try XCTUnwrap(invocations.first { $0.args.starts(with: ["worktree", "add"]) })
        let worktreePath = addInvocation.args[5]
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreePath))
        XCTAssertTrue(invocations.contains { $0.args.starts(with: ["worktree", "remove"]) })
        XCTAssertFalse(invocations.contains { $0.args.starts(with: ["update-ref", "-d"]) })
    }

    func testIdentityAwareCreateNeverDeletesCollidingBranchWhenAddFails() async throws {
        let fixture = try WorktreeCreationIdentityFixture(mode: .branchCollisionDuringAdd)
        defer { fixture.removeFiles() }

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.manager.create(
                projectPath: fixture.source.path,
                threadName: "Identity race",
                baseRef: nil,
                remoteName: nil,
                expectedProjectIdentity: fixture.sourceIdentity
            )
        }

        let invocations = await fixture.shell.invocations()
        XCTAssertTrue(invocations.contains { $0.args.starts(with: ["worktree", "add"]) })
        XCTAssertFalse(invocations.contains { $0.args.starts(with: ["update-ref", "-d"]) })
        let addInvocation = try XCTUnwrap(invocations.first { $0.args.starts(with: ["worktree", "add"]) })
        XCTAssertFalse(FileManager.default.fileExists(atPath: addInvocation.args[5]))
    }

    func testIdentityAwareCreateFailsClosedWhenBranchLookupErrors() async throws {
        let fixture = try WorktreeCreationIdentityFixture(mode: .branchLookupFailure)
        defer { fixture.removeFiles() }

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.manager.create(
                projectPath: fixture.source.path,
                threadName: "Identity race",
                baseRef: nil,
                remoteName: nil,
                expectedProjectIdentity: fixture.sourceIdentity
            )
        }

        let invocations = await fixture.shell.invocations()
        XCTAssertTrue(invocations.contains { $0.args.first == "show-ref" })
        XCTAssertFalse(invocations.contains { $0.args.starts(with: ["worktree", "add"]) })
    }

    func testIdentityAwareCreateRecordsProvenanceBeforeEachDestructiveStage() async throws {
        let fixture = try WorktreeCreationIdentityFixture(mode: .setupFailure)
        defer { fixture.removeFiles() }
        let recorder = WorktreeCreationProvenanceLog()

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.manager.create(
                projectPath: fixture.source.path,
                threadName: "Identity race",
                baseRef: nil,
                remoteName: nil,
                provenanceContext: WorktreeCreationProvenanceContext(
                    expectedProjectIdentity: fixture.sourceIdentity,
                    recorder: { recorder.records.append($0) }
                )
            )
        }

        let records = recorder.records
        XCTAssertEqual(records.map(\.branchIsOwned), [false, false, true])
        XCTAssertEqual(records.map(\.branchOID), [nil, nil, WorktreeTestObjectID.owned])
        XCTAssertNil(records[0].worktreeIdentity)
        XCTAssertNotNil(records[1].worktreeIdentity)
        XCTAssertEqual(records[1].worktreeIdentity, records[2].worktreeIdentity)
    }

    func testIdentityAwareRollbackPersistsAdvancedSetupHeadBeforeRemoval() async throws {
        let fixture = try WorktreeCreationIdentityFixture(mode: .advanceBranchDuringSetup)
        defer { fixture.removeFiles() }
        let recorder = WorktreeCreationProvenanceLog()

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.manager.create(
                projectPath: fixture.source.path,
                threadName: "Identity race",
                baseRef: nil,
                remoteName: nil,
                provenanceContext: WorktreeCreationProvenanceContext(
                    expectedProjectIdentity: fixture.sourceIdentity,
                    recorder: { recorder.records.append($0) }
                )
            )
        }

        XCTAssertEqual(
            recorder.records.map(\.branchOID),
            [nil, nil, WorktreeTestObjectID.owned, WorktreeTestObjectID.advanced]
        )
        let invocations = await fixture.shell.invocations()
        XCTAssertTrue(
            invocations.contains {
                $0.args == [
                    "update-ref", "-d", "--",
                    "refs/heads/\(recorder.records[2].branch)",
                    WorktreeTestObjectID.advanced
                ]
            }
        )
    }

    func testIdentityAwareCreateRejectsTargetParentReplacementAfterProvenanceWrite() async throws {
        let fixture = try WorktreeCreationIdentityFixture(mode: .setupFailure)
        defer { fixture.removeFiles() }
        let replacement = WorktreeParentReplacement(root: fixture.root)

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.manager.create(
                projectPath: fixture.source.path,
                threadName: "Identity race",
                baseRef: nil,
                remoteName: nil,
                provenanceContext: WorktreeCreationProvenanceContext(
                    expectedProjectIdentity: fixture.sourceIdentity,
                    recorder: { cleanup in try replacement.replaceParent(for: cleanup) }
                )
            )
        }

        let outsideTarget = try XCTUnwrap(replacement.outsideTarget)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outsideTarget.path))
        let invocations = await fixture.shell.invocations()
        XCTAssertFalse(invocations.contains { $0.args.starts(with: ["worktree", "add"]) })
    }

    func testIdentityAwareCreateRejectsTargetParentReplacementDuringDirectoryCreation() async throws {
        let directoryCreator = WorktreeParentSwapDirectoryCreator()
        let fixture = try WorktreeCreationIdentityFixture(
            mode: .setupFailure,
            directoryCreator: { try directoryCreator.create(atPath: $0) }
        )
        defer { fixture.removeFiles() }
        let recorder = WorktreeCreationProvenanceLog()

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.manager.create(
                projectPath: fixture.source.path,
                threadName: "Identity race",
                baseRef: nil,
                remoteName: nil,
                provenanceContext: WorktreeCreationProvenanceContext(
                    expectedProjectIdentity: fixture.sourceIdentity,
                    recorder: { recorder.records.append($0) }
                )
            )
        }

        XCTAssertTrue(directoryCreator.didCreateOutsideTarget)
        XCTAssertEqual(recorder.records.count, 1)
        XCTAssertNil(recorder.records[0].worktreeIdentity)
        XCTAssertFalse(recorder.records[0].branchIsOwned)
        let invocations = await fixture.shell.invocations()
        XCTAssertFalse(invocations.contains { $0.args.starts(with: ["worktree", "add"]) })
        XCTAssertFalse(invocations.contains { $0.args.starts(with: ["update-ref", "-d"]) })
    }
}

@MainActor
private struct WorktreeCreationIdentityFixture {
    let root: URL
    let source: URL
    let sourceReplacementSentinel: URL
    let sourceIdentity: TaskWorkspaceFileSystemIdentity
    let ownershipService: DefaultTaskWorkspaceOwnershipService
    let shell: WorktreeCreationIdentityShell
    let manager: DefaultWorktreeManager

    init(
        mode: WorktreeCreationIdentityShell.Mode,
        directoryCreator: DefaultWorktreeManager.DirectoryCreator? = nil
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorktreeCreationIdentityFixture-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let movedSource = root.appendingPathComponent("MovedSource", isDirectory: true)
        let worktreesBase = root.appendingPathComponent("Worktrees", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreesBase, withIntermediateDirectories: true)
        if mode != .replaceSourceAfterTargetLookup {
            try "{\"scripts\":{\"setup\":\"exit 1\"}}".write(
                to: source.appendingPathComponent(".alveary.json"),
                atomically: true,
                encoding: .utf8
            )
        }
        let ownershipService = DefaultTaskWorkspaceOwnershipService(
            privateWorkspacesRoot: root.appendingPathComponent("Private", isDirectory: true),
            worktreeOwnershipRecordsRoot: root.appendingPathComponent("Records", isDirectory: true)
        )
        var settings = AppSettings()
        settings.worktreesBaseDirectory = worktreesBase.path
        let shell = WorktreeCreationIdentityShell(
            mode: mode,
            source: source,
            movedSource: movedSource,
            root: root
        )
        self.root = root
        self.source = source
        self.sourceReplacementSentinel = source.appendingPathComponent("keep.txt")
        self.sourceIdentity = try ownershipService.directoryIdentity(at: source.path)
        self.ownershipService = ownershipService
        self.shell = shell
        self.manager = DefaultWorktreeManager(
            settingsService: InMemorySettingsService(current: settings),
            shell: shell,
            directoryCreator: directoryCreator ?? { path in
                try FileManager.default.createDirectory(
                    atPath: path,
                    withIntermediateDirectories: false
                )
            }
        )
    }

    func assertRollbackError() async throws -> WorktreeCreationRollbackError {
        do {
            _ = try await manager.create(
                projectPath: source.path,
                threadName: "Identity race",
                baseRef: nil,
                remoteName: nil,
                expectedProjectIdentity: sourceIdentity
            )
            throw WorktreeCreationIdentityTestError.expectedRollbackError
        } catch let error as WorktreeCreationRollbackError {
            return error
        }
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: root)
    }
}

private actor WorktreeCreationIdentityShell: ShellRunner {
    enum Mode: Sendable, Equatable {
        case replaceSourceAfterTargetLookup
        case replaceSourceDuringSetup
        case replaceWorktreeDuringSetup
        case replaceWorktreeBeforeAddReturns
        case cancelDuringAdd
        case branchCollisionDuringAdd
        case branchLookupFailure
        case setupFailure
        case advanceBranchDuringSetup
    }

    private let mode: Mode
    private let source: URL
    private let movedSource: URL
    private let root: URL
    private var recordedInvocations: [MockShellRunner.Invocation] = []
    private var createdWorktree: URL?
    private var createdBranch: String?
    private var currentHeadOID = WorktreeTestObjectID.owned

    init(mode: Mode, source: URL, movedSource: URL, root: URL) {
        self.mode = mode
        self.source = source
        self.movedSource = movedSource
        self.root = root
    }

    func run(
        executable: String,
        args: [String],
        in directory: String?,
        options: ShellRunOptions
    ) async throws -> ShellResult {
        recordedInvocations.append(.init(
            executable: executable,
            args: args,
            directory: directory,
            environment: options.environment,
            timeout: options.timeout,
            stdoutLimitBytes: options.stdoutLimitBytes,
            stderrLimitBytes: options.stderrLimitBytes,
            standardInput: options.standardInput
        ))
        if let earlyResult = try applyInvocationSideEffects(executable: executable, args: args) {
            return earlyResult
        }
        return makeResult(executable: executable, args: args)
    }

    private func applyInvocationSideEffects(
        executable: String,
        args: [String]
    ) throws -> ShellResult? {
        if mode == .replaceSourceAfterTargetLookup, args.first == "show-ref" {
            try replaceSource()
        } else if args.starts(with: ["worktree", "add"]), mode == .branchCollisionDuringAdd {
            return ShellResult(
                stdout: "",
                stderr: "fatal: a branch named 'alveary/identity-race' already exists",
                exitCode: 128,
                stdoutWasTruncated: false,
                stderrWasTruncated: false
            )
        } else if args.starts(with: ["worktree", "add"]) {
            let worktree = URL(fileURLWithPath: args[5], isDirectory: true)
            try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
            createdWorktree = worktree
            createdBranch = args[4]
            if mode == .replaceWorktreeBeforeAddReturns {
                try replaceWorktree()
            } else if mode == .cancelDuringAdd {
                try Data("partial".utf8).write(to: worktree.appendingPathComponent("partial.txt"))
                throw CancellationError()
            }
        } else if executable == "/bin/sh" {
            switch mode {
            case .replaceSourceDuringSetup:
                try replaceSource()
            case .replaceWorktreeDuringSetup:
                try replaceWorktree()
            case .advanceBranchDuringSetup:
                currentHeadOID = WorktreeTestObjectID.advanced
            case .replaceSourceAfterTargetLookup,
                 .replaceWorktreeBeforeAddReturns,
                 .cancelDuringAdd,
                 .branchCollisionDuringAdd,
                 .branchLookupFailure,
                 .setupFailure:
                break
            }
        }
        return nil
    }

    private func makeResult(executable: String, args: [String]) -> ShellResult {
        if args == ["worktree", "list", "--porcelain"],
           let createdWorktree,
           let createdBranch {
            return ShellResult(
                stdout: "worktree \(createdWorktree.path)\nHEAD \(currentHeadOID)\nbranch refs/heads/\(createdBranch)\n\n",
                stderr: "",
                exitCode: 0,
                stdoutWasTruncated: false,
                stderrWasTruncated: false
            )
        }
        let exitCode: Int32
        if args.first == "show-ref" {
            exitCode = mode == .branchLookupFailure ? 128 : 1
        } else {
            exitCode = 0
        }
        return ShellResult(
            stdout: "",
            stderr: executable == "/bin/sh" ? "setup failed" : "",
            exitCode: executable == "/bin/sh" ? 1 : exitCode,
            stdoutWasTruncated: false,
            stderrWasTruncated: false
        )
    }

    func invocations() -> [MockShellRunner.Invocation] {
        recordedInvocations
    }

    private func replaceSource() throws {
        try FileManager.default.moveItem(at: source, to: movedSource)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: source.appendingPathComponent("keep.txt"))
    }

    private func replaceWorktree() throws {
        guard let createdWorktree else {
            throw WorktreeCreationIdentityTestError.missingCreatedWorktree
        }
        let movedWorktree = root.appendingPathComponent("MovedWorktree", isDirectory: true)
        try FileManager.default.moveItem(at: createdWorktree, to: movedWorktree)
        try FileManager.default.createDirectory(at: createdWorktree, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: createdWorktree.appendingPathComponent("keep.txt"))
    }
}

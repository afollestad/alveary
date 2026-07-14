import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testDeleteTaskPreservesReplacementAtOwnedWorktreePath() async throws {
        let fixture = try SidebarTestFixture()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-task-replacement-worktree-\(UUID().uuidString)", isDirectory: true)
        let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
        let worktreeRoot = root.appendingPathComponent("Worktree", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try fixture.taskWorkspaceOwnershipService.registerOwnedWorktree(
            at: worktreeRoot.path,
            sourceProjectPath: sourceRoot.path,
            grantedRoots: []
        )
        try FileManager.default.removeItem(at: worktreeRoot)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        let sentinelURL = worktreeRoot.appendingPathComponent("keep.txt")
        try Data("user data".utf8).write(to: sentinelURL)
        let task = AgentThread(
            name: "Replacement worktree task",
            branch: "alveary/task-run",
            mode: .task,
            taskWorkspaceDescriptor: workspace
        )
        task.conversations = [Conversation(id: "replacement-worktree-task", provider: "codex", thread: task)]
        fixture.context.insert(task)
        try fixture.context.save()

        do {
            try await fixture.viewModel.deleteThread(task)
            XCTFail("Expected Task cleanup to report that the replacement was preserved")
        } catch let error as SidebarViewModelError {
            guard case .threadDeleteCleanupFailed = error else {
                return XCTFail("Expected a post-commit Task cleanup failure, got \(error)")
            }
        }

        XCTAssertNil(fixture.context.resolveThread(id: task.persistentModelID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinelURL.path))
        XCTAssertThrowsError(try fixture.taskWorkspaceOwnershipService.validateOwnedWorkspace(workspace)) { error in
            guard case TaskWorkspaceOwnershipError.missingOwnershipMarker = error else {
                return XCTFail("Expected the stale sidecar to be removed, got \(error)")
            }
        }
    }

    func testDeleteTaskClearsSidecarWhenOwnedWorktreeDirectoryIsAlreadyMissing() async throws {
        let fixture = try SidebarTestFixture()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-task-missing-worktree-\(UUID().uuidString)", isDirectory: true)
        let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
        let worktreeRoot = root.appendingPathComponent("Worktree", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try fixture.taskWorkspaceOwnershipService.registerOwnedWorktree(
            at: worktreeRoot.path,
            sourceProjectPath: sourceRoot.path,
            grantedRoots: []
        )
        try FileManager.default.removeItem(at: worktreeRoot)
        let task = AgentThread(
            name: "Missing worktree task",
            branch: "alveary/task-run",
            mode: .task,
            taskWorkspaceDescriptor: workspace
        )
        task.conversations = [Conversation(id: "missing-worktree-task", provider: "codex", thread: task)]
        fixture.context.insert(task)
        try fixture.context.save()

        try await fixture.viewModel.deleteThread(task)

        let branchCalls = await fixture.worktreeManager.deleteBranchCalls()
        XCTAssertTrue(branchCalls.isEmpty)
        XCTAssertThrowsError(try fixture.taskWorkspaceOwnershipService.validateOwnedWorkspace(workspace))
    }

    func testDeleteUnregisteredTaskWorktreeDoesNotDeleteBranchFromReplacementSourceRepository() async throws {
        let fixture = try SidebarTestFixture()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-task-replacement-source-\(UUID().uuidString)", isDirectory: true)
        let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
        let worktreeRoot = root.appendingPathComponent("Worktree", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try fixture.taskWorkspaceOwnershipService.registerOwnedWorktree(
            at: worktreeRoot.path,
            sourceProjectPath: sourceRoot.path,
            grantedRoots: []
        )
        try FileManager.default.removeItem(at: sourceRoot)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        await fixture.worktreeManager.setListResult([
            WorktreeInfo(path: worktreeRoot.path, branch: "alveary/task-run")
        ])
        let task = AgentThread(
            name: "Replacement source task",
            branch: "alveary/task-run",
            mode: .task,
            taskWorkspaceDescriptor: workspace
        )
        task.conversations = [Conversation(id: "replacement-source-task", provider: "codex", thread: task)]
        fixture.context.insert(task)
        try fixture.context.save()

        try await fixture.viewModel.deleteThread(task)

        let branchCalls = await fixture.worktreeManager.deleteBranchCalls()
        let removeCalls = await fixture.worktreeManager.removeCalls()
        XCTAssertTrue(branchCalls.isEmpty)
        XCTAssertTrue(removeCalls.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeRoot.path))
    }

    func testDeleteTaskFinalizesOwnedWorkspaceAfterGitRemovalFailure() async throws {
        let fixture = try SidebarTestFixture()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-task-git-removal-failure-\(UUID().uuidString)", isDirectory: true)
        let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
        let worktreeRoot = root.appendingPathComponent("Worktree", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try fixture.taskWorkspaceOwnershipService.registerOwnedWorktree(
            at: worktreeRoot.path,
            sourceProjectPath: sourceRoot.path,
            grantedRoots: []
        )
        let task = AgentThread(
            name: "Failed Git cleanup task",
            branch: "alveary/task-run",
            mode: .task,
            taskWorkspaceDescriptor: workspace
        )
        task.conversations = [Conversation(id: "failed-git-cleanup-task", provider: "codex", thread: task)]
        fixture.context.insert(task)
        try fixture.context.save()
        await fixture.worktreeManager.setListResult([
            WorktreeInfo(path: worktreeRoot.path, branch: "alveary/task-run")
        ])
        await fixture.worktreeManager.setRemoveError(.removeFailed)

        do {
            try await fixture.viewModel.deleteThread(task)
            XCTFail("Expected Task cleanup to report the Git removal failure")
        } catch let error as SidebarViewModelError {
            guard case .threadDeleteCleanupFailed = error else {
                return XCTFail("Expected a post-commit Task cleanup failure, got \(error)")
            }
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeRoot.path))
        XCTAssertThrowsError(try fixture.taskWorkspaceOwnershipService.validateOwnedWorkspace(workspace))
    }

    func testDeleteTerminalScheduledTaskShellWithoutWorkspace() async throws {
        let fixture = try SidebarTestFixture()
        let run = makeSidebarScheduledRun(status: .failure)
        let task = makeScheduledTaskShell(run: run, conversationID: "failed-scheduled-shell")
        fixture.context.insert(run)
        fixture.context.insert(task)
        try fixture.context.save()
        let threadID = task.persistentModelID
        let runID = run.persistentModelID

        try await fixture.viewModel.deleteThread(task)

        XCTAssertNil(fixture.context.resolveThread(id: threadID))
        XCTAssertNil(fixture.context.resolveScheduledTaskRun(id: runID)?.thread)
    }

    func testDeleteScheduledTaskShellRejectsInvalidPreparedWorkspaceMetadata() async throws {
        let fixture = try SidebarTestFixture()
        let run = makeSidebarScheduledRun(status: .failure)
        run.preparedWorkspaceRoot = "/tmp/unresolved-scheduled-workspace"
        run.preparedWorkspaceOwnershipStrategy = .privateOwned
        run.preparedWorkspaceMarkerID = "invalid-marker"
        let task = makeScheduledTaskShell(run: run, conversationID: "ambiguous-scheduled-shell")
        fixture.context.insert(run)
        fixture.context.insert(task)
        try fixture.context.save()

        do {
            try await fixture.viewModel.deleteThread(task)
            XCTFail("Expected unresolved workspace metadata to prevent deletion")
        } catch let error as SidebarViewModelError {
            guard case .threadMissingDeletionMetadata = error else {
                return XCTFail("Expected missing deletion metadata error, got \(error)")
            }
        }

        XCTAssertNotNil(fixture.context.resolveThread(id: task.persistentModelID))
    }

    func testDeleteScheduledTaskShellRejectsOrphanedThreadWorktreeMetadata() async throws {
        let fixture = try SidebarTestFixture()
        let run = makeSidebarScheduledRun(status: .failure)
        let task = makeScheduledTaskShell(run: run, conversationID: "ambiguous-thread-worktree")
        task.branch = "alveary/unresolved"
        fixture.context.insert(run)
        fixture.context.insert(task)
        try fixture.context.save()

        do {
            try await fixture.viewModel.deleteThread(task)
            XCTFail("Expected orphaned worktree metadata to prevent deletion")
        } catch let error as SidebarViewModelError {
            guard case .threadMissingTaskWorkspace = error else {
                return XCTFail("Expected missing Task workspace error, got \(error)")
            }
        }

        XCTAssertNotNil(fixture.context.resolveThread(id: task.persistentModelID))
    }

    func testDeleteScheduledTaskShellRetriesPendingWorktreeCleanup() async throws {
        let fixture = try SidebarTestFixture()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-pending-scheduled-cleanup-\(UUID().uuidString)", isDirectory: true)
        let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
        let worktreeRoot = root.appendingPathComponent("Worktree", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try fixture.taskWorkspaceOwnershipService.registerOwnedWorktree(
            at: worktreeRoot.path,
            sourceProjectPath: sourceRoot.path,
            grantedRoots: []
        )
        let sourceIdentity = try fixture.taskWorkspaceOwnershipService.directoryIdentity(at: sourceRoot.path)
        let worktreeIdentity = try fixture.taskWorkspaceOwnershipService.directoryIdentity(at: worktreeRoot.path)
        let run = makeSidebarScheduledRun(status: .failure)
        run.setPendingWorktreeCleanup(try XCTUnwrap(ScheduledWorktreeCleanupProvenance(
            sourceProjectPath: sourceRoot.path,
            worktreePath: worktreeRoot.path,
            branch: "alveary/pending-scheduled-cleanup",
            sourceProjectIdentity: sourceIdentity,
            worktreeIdentity: worktreeIdentity,
            ownershipMarkerID: workspace.ownershipMarkerID,
            ownershipSourceProjectPath: workspace.sourceProjectPath
        )))
        let task = makeScheduledTaskShell(run: run, conversationID: "pending-scheduled-cleanup")
        fixture.context.insert(run)
        fixture.context.insert(task)
        try fixture.context.save()
        let runID = run.persistentModelID
        await fixture.worktreeManager.setListResult([
            WorktreeInfo(
                path: worktreeRoot.path,
                branch: "alveary/pending-scheduled-cleanup",
                headOID: "pending-head"
            )
        ])

        try await fixture.viewModel.deleteThread(task)

        let removeCalls = await fixture.worktreeManager.removeCalls()
        let branchCalls = await fixture.worktreeManager.deleteBranchCalls()
        XCTAssertEqual(removeCalls.count, 1)
        XCTAssertNil(removeCalls.first?.branch)
        XCTAssertEqual(branchCalls.map(\.branch), ["alveary/pending-scheduled-cleanup"])
        XCTAssertEqual(branchCalls.map(\.expectedOID), ["pending-head"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeRoot.path))
        XCTAssertFalse(try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: runID)).hasPendingWorktreeCleanupMetadata)
    }

    func testDeleteScheduledTaskPreservesUnregisteredBranchAfterOwnedWorktreeRemovalCrashAndStoreReopen() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-pending-cleanup-reopen-\(UUID().uuidString)", isDirectory: true)
        let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
        let worktreeRoot = root.appendingPathComponent("Worktree", isDirectory: true)
        let ownershipService = DefaultTaskWorkspaceOwnershipService(
            privateWorkspacesRoot: root.appendingPathComponent("Private", isDirectory: true),
            worktreeOwnershipRecordsRoot: root.appendingPathComponent("Records", isDirectory: true)
        )
        let configuration = ModelConfiguration(url: root.appendingPathComponent("Alveary.store"))
        let occurrenceID = "pending-cleanup-reopen-occurrence"
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try persistPendingWorktreeCleanupCrashState(
            configuration: configuration,
            ownershipService: ownershipService,
            sourceRoot: sourceRoot,
            worktreeRoot: worktreeRoot,
            occurrenceID: occurrenceID
        )

        let reopenedFixture = try SidebarTestFixture(
            taskWorkspaceOwnershipService: ownershipService,
            modelConfiguration: configuration
        )
        let reopenedRun = try XCTUnwrap(
            reopenedFixture.context.fetch(FetchDescriptor<ScheduledTaskRun>())
                .first { $0.occurrenceID == occurrenceID }
        )
        let reopenedTask = try XCTUnwrap(reopenedRun.thread)

        try await reopenedFixture.viewModel.deleteThread(reopenedTask)

        let persistedRun = try XCTUnwrap(
            reopenedFixture.context.fetch(FetchDescriptor<ScheduledTaskRun>())
                .first { $0.occurrenceID == occurrenceID }
        )
        XCTAssertFalse(persistedRun.hasPendingWorktreeCleanupMetadata)
        XCTAssertNil(persistedRun.thread)
        let branchCalls = await reopenedFixture.worktreeManager.deleteBranchCalls()
        XCTAssertTrue(branchCalls.isEmpty)
    }

    func testDeletePendingUnregisteredWorktreeRemovesExactDirectoryWithoutDeletingUnprovenBranch() async throws {
        let fixture = try SidebarTestFixture()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-pending-unregistered-\(UUID().uuidString)", isDirectory: true)
        let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
        let worktreeRoot = root.appendingPathComponent("Worktree", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceIdentity = try fixture.taskWorkspaceOwnershipService.directoryIdentity(at: sourceRoot.path)
        let worktreeIdentity = try fixture.taskWorkspaceOwnershipService.directoryIdentity(at: worktreeRoot.path)
        let run = makeSidebarScheduledRun(status: .failure)
        run.setPendingWorktreeCleanup(try XCTUnwrap(ScheduledWorktreeCleanupProvenance(
            sourceProjectPath: sourceRoot.path,
            worktreePath: worktreeRoot.path,
            branch: "alveary/unproven-branch",
            sourceProjectIdentity: sourceIdentity,
            worktreeIdentity: worktreeIdentity,
            branchIsOwned: false,
            ownershipMarkerID: UUID().uuidString.lowercased(),
            ownershipSourceProjectPath: sourceRoot.path
        )))
        let task = makeScheduledTaskShell(run: run, conversationID: "pending-unregistered")
        fixture.context.insert(run)
        fixture.context.insert(task)
        try fixture.context.save()

        try await fixture.viewModel.deleteThread(task)

        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeRoot.path))
        XCTAssertNil(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID)?.pendingWorktreeCleanup)
        let branchCalls = await fixture.worktreeManager.deleteBranchCalls()
        XCTAssertTrue(branchCalls.isEmpty)
    }
}

@MainActor
private func persistPendingWorktreeCleanupCrashState(
    configuration: ModelConfiguration,
    ownershipService: DefaultTaskWorkspaceOwnershipService,
    sourceRoot: URL,
    worktreeRoot: URL,
    occurrenceID: String
) throws {
    let fixture = try SidebarTestFixture(
        taskWorkspaceOwnershipService: ownershipService,
        modelConfiguration: configuration
    )
    let workspace = try ownershipService.registerOwnedWorktree(
        at: worktreeRoot.path,
        sourceProjectPath: sourceRoot.path,
        grantedRoots: []
    )
    let sourceIdentity = try ownershipService.directoryIdentity(at: sourceRoot.path)
    let worktreeIdentity = try ownershipService.directoryIdentity(at: worktreeRoot.path)
    let run = makeSidebarScheduledRun(status: .failure)
    run.occurrenceID = occurrenceID
    run.workspaceKindRawValueSnapshot = ScheduledTaskWorkspaceKind.project.rawValue
    run.workspaceStrategyRawValueSnapshot = ScheduledTaskWorkspaceStrategy.worktree.rawValue
    run.projectPathSnapshot = sourceRoot.path
    run.setPendingWorktreeCleanup(try XCTUnwrap(ScheduledWorktreeCleanupProvenance(
        sourceProjectPath: sourceRoot.path,
        worktreePath: worktreeRoot.path,
        branch: "alveary/pending-cleanup-reopen",
        sourceProjectIdentity: sourceIdentity,
        worktreeIdentity: worktreeIdentity,
        ownershipMarkerID: workspace.ownershipMarkerID,
        ownershipSourceProjectPath: workspace.sourceProjectPath
    )))
    let task = makeScheduledTaskShell(run: run, conversationID: "pending-cleanup-reopen")
    fixture.context.insert(run)
    fixture.context.insert(task)
    try fixture.context.save()

    // Simulate a crash after filesystem cleanup but before the persisted provenance is cleared.
    try ownershipService.removeOwnedWorkspace(workspace)
}

@MainActor
private func makeSidebarScheduledRun(status: ScheduledTaskRunStatus) -> ScheduledTaskRun {
    ScheduledTaskRun(
        occurrenceID: UUID().uuidString,
        definitionID: "definition-\(UUID().uuidString)",
        definitionRevision: 1,
        occurrenceAt: Date(timeIntervalSince1970: 1_800_000_000),
        triggerKind: .scheduled,
        status: status,
        titleSnapshot: "Scheduled task",
        promptSnapshot: "Run scheduled work.",
        timeZoneIdentifierSnapshot: "America/Chicago",
        providerIDSnapshot: "codex",
        effortSnapshot: "high",
        permissionModeSnapshot: "default",
        workspaceKindSnapshot: .privateWorkspace,
        workspaceStrategySnapshot: .worktree
    )
}

@MainActor
private func makeScheduledTaskShell(
    run: ScheduledTaskRun,
    conversationID: String
) -> AgentThread {
    let thread = AgentThread(
        name: "Scheduled task",
        mode: .task,
        scheduledTaskRun: run
    )
    thread.conversations = [
        Conversation(id: conversationID, provider: "codex", thread: thread)
    ]
    run.thread = thread
    return thread
}

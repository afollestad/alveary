import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testDeleteOwnedTaskWorktreeRechecksSourceIdentityAfterListing() async throws {
        let fixture = try SidebarTestFixture()
        let paths = try makeCleanupRacePaths(prefix: "task-worktree-list-race")
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let workspace = try fixture.taskWorkspaceOwnershipService.registerOwnedWorktree(
            at: paths.worktree.path,
            sourceProjectPath: paths.source.path,
            grantedRoots: []
        )
        await fixture.worktreeManager.setListResult([
            WorktreeInfo(path: paths.worktree.path, branch: "alveary/list-race")
        ])
        await fixture.worktreeManager.setListHook {
            replaceCleanupRaceSource(paths)
        }
        let task = AgentThread(
            name: "Source replacement during list",
            branch: "alveary/list-race",
            mode: .task,
            taskWorkspaceDescriptor: workspace
        )
        task.conversations = [Conversation(id: "task-worktree-list-race", provider: "codex", thread: task)]
        fixture.context.insert(task)
        try fixture.context.save()

        try await fixture.viewModel.deleteThread(task)

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.replacementSentinel.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.worktree.path))
        let removeCalls = await fixture.worktreeManager.removeCalls()
        let branchCalls = await fixture.worktreeManager.deleteBranchCalls()
        XCTAssertTrue(removeCalls.isEmpty)
        XCTAssertTrue(branchCalls.isEmpty)
    }

    func testDeletePendingScheduledCleanupRechecksSourceIdentityAfterListing() async throws {
        let fixture = try SidebarTestFixture()
        let paths = try makeCleanupRacePaths(prefix: "pending-worktree-list-race")
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let workspace = try fixture.taskWorkspaceOwnershipService.registerOwnedWorktree(
            at: paths.worktree.path,
            sourceProjectPath: paths.source.path,
            grantedRoots: []
        )
        let sourceIdentity = try fixture.taskWorkspaceOwnershipService.directoryIdentity(at: paths.source.path)
        let (task, runID) = try insertPendingCleanupRaceTask(
            fixture: fixture,
            paths: paths,
            workspace: workspace,
            sourceIdentity: sourceIdentity
        )
        await fixture.worktreeManager.setListResult([
            WorktreeInfo(path: paths.worktree.path, branch: "alveary/pending-list-race")
        ])
        await fixture.worktreeManager.setListHook {
            replaceCleanupRaceSource(paths)
        }

        await assertPendingScheduledCleanupDefersDeletion(fixture: fixture, task: task)

        let persistedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: runID))
        let pendingCleanup = try XCTUnwrap(persistedRun.pendingWorktreeCleanup)
        XCTAssertFalse(pendingCleanup.branchIsOwned)
        XCTAssertEqual(pendingCleanup.ownedWorkspaceDescriptor, workspace)
        XCTAssertNotNil(pendingCleanup.worktreeIdentity)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.replacementSentinel.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.worktree.path))

        try await fixture.viewModel.deleteThread(task)

        let completedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: runID))
        XCTAssertNil(completedRun.pendingWorktreeCleanup)
        XCTAssertNil(completedRun.thread)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.replacementSentinel.path))
        let removeCalls = await fixture.worktreeManager.removeCalls()
        let branchCalls = await fixture.worktreeManager.deleteBranchCalls()
        XCTAssertTrue(removeCalls.isEmpty)
        XCTAssertTrue(branchCalls.isEmpty)
    }

    func testDeletePendingScheduledCleanupCompletesOnRetryWhenSourceIsMissing() async throws {
        let fixture = try SidebarTestFixture()
        let paths = try makeCleanupRacePaths(prefix: "pending-worktree-missing-source")
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let workspace = try fixture.taskWorkspaceOwnershipService.registerOwnedWorktree(
            at: paths.worktree.path,
            sourceProjectPath: paths.source.path,
            grantedRoots: []
        )
        let sourceIdentity = try fixture.taskWorkspaceOwnershipService.directoryIdentity(at: paths.source.path)
        let (task, runID) = try insertPendingCleanupRaceTask(
            fixture: fixture,
            paths: paths,
            workspace: workspace,
            sourceIdentity: sourceIdentity
        )
        try FileManager.default.removeItem(at: paths.source)

        await assertPendingScheduledCleanupDefersDeletion(fixture: fixture, task: task)

        let pendingRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: runID))
        let pendingCleanup = try XCTUnwrap(pendingRun.pendingWorktreeCleanup)
        XCTAssertFalse(pendingCleanup.branchIsOwned)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.worktree.path))
        XCTAssertThrowsError(try fixture.taskWorkspaceOwnershipService.validateOwnedWorkspace(workspace))

        try await fixture.viewModel.deleteThread(task)

        let completedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: runID))
        XCTAssertNil(completedRun.pendingWorktreeCleanup)
        XCTAssertNil(completedRun.thread)
        let removeCalls = await fixture.worktreeManager.removeCalls()
        let branchCalls = await fixture.worktreeManager.deleteBranchCalls()
        XCTAssertTrue(removeCalls.isEmpty)
        XCTAssertTrue(branchCalls.isEmpty)
    }

    func testDeletePendingScheduledCleanupCompletesOnRetryAfterRepeatedGitListFailure() async throws {
        let fixture = try SidebarTestFixture()
        let paths = try makeCleanupRacePaths(prefix: "pending-worktree-list-failure")
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let workspace = try fixture.taskWorkspaceOwnershipService.registerOwnedWorktree(
            at: paths.worktree.path,
            sourceProjectPath: paths.source.path,
            grantedRoots: []
        )
        let sourceIdentity = try fixture.taskWorkspaceOwnershipService.directoryIdentity(at: paths.source.path)
        let (task, runID) = try insertPendingCleanupRaceTask(
            fixture: fixture,
            paths: paths,
            workspace: workspace,
            sourceIdentity: sourceIdentity
        )
        await fixture.worktreeManager.setListResult([], error: .listFailed)

        await assertPendingScheduledCleanupDefersDeletion(fixture: fixture, task: task)

        let pendingRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: runID))
        let pendingCleanup = try XCTUnwrap(pendingRun.pendingWorktreeCleanup)
        XCTAssertFalse(pendingCleanup.branchIsOwned)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.worktree.path))
        XCTAssertThrowsError(try fixture.taskWorkspaceOwnershipService.validateOwnedWorkspace(workspace))

        try await fixture.viewModel.deleteThread(task)

        let completedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: runID))
        XCTAssertNil(completedRun.pendingWorktreeCleanup)
        XCTAssertNil(completedRun.thread)
        let removeCalls = await fixture.worktreeManager.removeCalls()
        let branchCalls = await fixture.worktreeManager.deleteBranchCalls()
        XCTAssertTrue(removeCalls.isEmpty)
        XCTAssertTrue(branchCalls.isEmpty)
    }
}

@MainActor
private func assertPendingScheduledCleanupDefersDeletion(
    fixture: SidebarTestFixture,
    task: AgentThread,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await fixture.viewModel.deleteThread(task)
        XCTFail("Expected pending scheduled cleanup to defer deletion", file: file, line: line)
    } catch let error as SidebarViewModelError {
        guard case .threadDeletePreparationFailed = error else {
            return XCTFail("Expected a pre-commit cleanup failure, got \(error)", file: file, line: line)
        }
    } catch {
        XCTFail("Expected a sidebar cleanup failure, got \(error)", file: file, line: line)
    }
}

private struct CleanupRacePaths: Sendable {
    let root: URL
    let source: URL
    let movedSource: URL
    let worktree: URL
    let replacementSentinel: URL
}

private func makeCleanupRacePaths(prefix: String) throws -> CleanupRacePaths {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("alveary-\(prefix)-\(UUID().uuidString)", isDirectory: true)
    let source = root.appendingPathComponent("Source", isDirectory: true)
    let movedSource = root.appendingPathComponent("MovedSource", isDirectory: true)
    let worktree = root.appendingPathComponent("Worktree", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
    return CleanupRacePaths(
        root: root,
        source: source,
        movedSource: movedSource,
        worktree: worktree,
        replacementSentinel: source.appendingPathComponent("keep.txt")
    )
}

private func replaceCleanupRaceSource(_ paths: CleanupRacePaths) {
    try? FileManager.default.moveItem(at: paths.source, to: paths.movedSource)
    try? FileManager.default.createDirectory(at: paths.source, withIntermediateDirectories: true)
    try? Data("keep".utf8).write(to: paths.replacementSentinel)
}

@MainActor
private func insertPendingCleanupRaceTask(
    fixture: SidebarTestFixture,
    paths: CleanupRacePaths,
    workspace: TaskWorkspaceDescriptor,
    sourceIdentity: TaskWorkspaceFileSystemIdentity
) throws -> (AgentThread, PersistentIdentifier) {
    let run = makeCleanupRaceRun()
    let worktreeIdentity = try fixture.taskWorkspaceOwnershipService.directoryIdentity(at: paths.worktree.path)
    run.setPendingWorktreeCleanup(try XCTUnwrap(ScheduledWorktreeCleanupProvenance(
        sourceProjectPath: paths.source.path,
        worktreePath: paths.worktree.path,
        branch: "alveary/pending-list-race",
        sourceProjectIdentity: sourceIdentity,
        worktreeIdentity: worktreeIdentity,
        ownershipMarkerID: workspace.ownershipMarkerID,
        ownershipSourceProjectPath: workspace.sourceProjectPath
    )))
    let task = AgentThread(
        name: "Pending source replacement during list",
        mode: .task,
        scheduledTaskRun: run
    )
    task.conversations = [Conversation(id: "pending-worktree-list-race", provider: "codex", thread: task)]
    fixture.context.insert(run)
    fixture.context.insert(task)
    try fixture.context.save()
    return (task, run.persistentModelID)
}

@MainActor
private func makeCleanupRaceRun() -> ScheduledTaskRun {
    ScheduledTaskRun(
        occurrenceID: UUID().uuidString,
        definitionID: "definition-\(UUID().uuidString)",
        definitionRevision: 1,
        occurrenceAt: Date(timeIntervalSince1970: 1_800_000_000),
        triggerKind: .scheduled,
        status: .failure,
        titleSnapshot: "Scheduled task",
        promptSnapshot: "Run scheduled work.",
        timeZoneIdentifierSnapshot: "America/Chicago",
        providerIDSnapshot: "codex",
        effortSnapshot: "high",
        permissionModeSnapshot: "default",
        workspaceKindSnapshot: .project,
        workspaceStrategySnapshot: .worktree
    )
}

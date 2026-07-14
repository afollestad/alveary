import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testPendingCleanupRetriesExactBranchAfterDeletionFailure() async throws {
        let state = try PendingBranchCleanupState(removalFailureCount: 0)
        defer { state.removeFiles() }
        let taskID = state.task.persistentModelID
        await state.fixture.worktreeManager.setListResult([
            WorktreeInfo(path: state.worktreeRoot.path, branch: state.branch, headOID: "owned-head")
        ])
        await state.fixture.worktreeManager.setRetryableDeleteBranchError(.deleteBranchFailed)

        do {
            try await state.fixture.viewModel.deleteThread(state.task)
            XCTFail("Expected the injected branch deletion failure")
        } catch let error as SidebarViewModelError {
            guard case .threadDeletePreparationFailed = error else {
                return XCTFail("Expected pre-commit cleanup failure, got \(error)")
            }
        }

        let retainedRun = try XCTUnwrap(state.fixture.context.resolveScheduledTaskRun(id: state.runID))
        let retainedCleanup = try XCTUnwrap(retainedRun.pendingWorktreeCleanup)
        XCTAssertTrue(retainedCleanup.branchIsOwned)
        XCTAssertEqual(retainedCleanup.branchOID, "owned-head")
        XCTAssertNil(retainedCleanup.ownedWorkspaceDescriptor)
        XCTAssertNil(retainedCleanup.worktreeIdentity)
        XCTAssertFalse(FileManager.default.fileExists(atPath: state.worktreeRoot.path))
        XCTAssertNotNil(state.fixture.context.resolveThread(id: taskID))
        XCTAssertNotNil(
            state.fixture.context.resolveConversation(conversationID: "pending-cleanup-first-attempt")
        )

        await state.fixture.worktreeManager.setRetryableDeleteBranchError(nil)
        await state.fixture.worktreeManager.setListResult([])

        try await state.fixture.viewModel.deleteThread(state.task)

        let branchCalls = await state.fixture.worktreeManager.deleteBranchCalls()
        XCTAssertEqual(branchCalls.map(\.expectedOID), ["owned-head", "owned-head"])
        XCTAssertNil(state.fixture.context.resolveThread(id: taskID))
        XCTAssertFalse(
            try XCTUnwrap(state.fixture.context.resolveScheduledTaskRun(id: state.runID)).hasPendingWorktreeCleanupMetadata
        )
    }

    func testOverlappingPendingCleanupCannotConsumeInFlightRetirementFence() async throws {
        let state = try PendingBranchCleanupState(removalFailureCount: 0)
        defer { state.removeFiles() }
        let taskID = state.task.persistentModelID
        let gate = SidebarMockBranchDeletionGate()
        await state.fixture.worktreeManager.setListResult([
            WorktreeInfo(path: state.worktreeRoot.path, branch: state.branch, headOID: "owned-head")
        ])
        await state.fixture.worktreeManager.setRetryableDeleteBranchError(.deleteBranchFailed)
        await state.fixture.worktreeManager.setDeleteBranchGate(gate)

        let firstDelete = Task { @MainActor in
            do {
                try await state.fixture.viewModel.deleteThread(state.task)
                return false
            } catch let error as SidebarViewModelError {
                guard case .threadDeletePreparationFailed = error else {
                    return false
                }
                return true
            } catch {
                return false
            }
        }
        await gate.waitUntilEntered()

        let overlappingCleanupWasRejected = await rejectsOverlappingPendingCleanup(
            state.fixture.viewModel,
            task: state.task
        )
        XCTAssertTrue(overlappingCleanupWasRejected)
        XCTAssertNotNil(state.fixture.context.resolveThread(id: taskID))

        await gate.release()
        let firstDeleteFailedBeforeCommit = await firstDelete.value
        XCTAssertTrue(firstDeleteFailedBeforeCommit)

        let retainedRun = try XCTUnwrap(state.fixture.context.resolveScheduledTaskRun(id: state.runID))
        let retainedCleanup = try XCTUnwrap(retainedRun.pendingWorktreeCleanup)
        XCTAssertTrue(retainedCleanup.branchIsOwned)
        XCTAssertEqual(retainedCleanup.branchOID, "owned-head")
        XCTAssertNotNil(state.fixture.context.resolveThread(id: taskID))

        await state.fixture.worktreeManager.setDeleteBranchGate(nil)
        await state.fixture.worktreeManager.setRetryableDeleteBranchError(nil)
        await state.fixture.worktreeManager.setListResult([])
        try await state.fixture.viewModel.deleteThread(state.task)

        let branchCalls = await state.fixture.worktreeManager.deleteBranchCalls()
        XCTAssertEqual(branchCalls.map(\.expectedOID), ["owned-head", "owned-head"])
        XCTAssertNil(state.fixture.context.resolveThread(id: taskID))
    }

    func testPendingCleanupDoesNotDeleteRecreatedBranchAfterOwnershipCleanupRetry() async throws {
        let state = try PendingBranchCleanupState()
        defer { state.removeFiles() }
        let taskID = state.task.persistentModelID
        await state.fixture.worktreeManager.setListResult([
            WorktreeInfo(path: state.worktreeRoot.path, branch: state.branch, headOID: "owned-head")
        ])

        do {
            try await state.fixture.viewModel.deleteThread(state.task)
            XCTFail("Expected the injected ownership cleanup failure")
        } catch let error as SidebarViewModelError {
            guard case .threadDeletePreparationFailed = error else {
                return XCTFail("Expected pre-commit cleanup failure, got \(error)")
            }
        }

        let retainedRun = try XCTUnwrap(state.fixture.context.resolveScheduledTaskRun(id: state.runID))
        let firstBranchCalls = await state.fixture.worktreeManager.deleteBranchCalls()
        XCTAssertEqual(retainedRun.pendingWorktreeCleanup?.branchIsOwned, false)
        XCTAssertEqual(retainedRun.pendingWorktreeCleanup?.branchOID, "owned-head")
        XCTAssertEqual(firstBranchCalls.map(\.branch), [state.branch])
        XCTAssertEqual(firstBranchCalls.map(\.expectedOID), ["owned-head"])
        XCTAssertNotNil(state.fixture.context.resolveThread(id: taskID))

        // A recreated branch with this name must survive the ownership-only retry.
        await state.fixture.worktreeManager.setListResult([])

        try await state.fixture.viewModel.deleteThread(state.task)

        let branchCalls = await state.fixture.worktreeManager.deleteBranchCalls()
        XCTAssertEqual(branchCalls.map(\.branch), [state.branch])
        XCTAssertNil(state.fixture.context.resolveThread(id: taskID))
        XCTAssertFalse(
            try XCTUnwrap(state.fixture.context.resolveScheduledTaskRun(id: state.runID)).hasPendingWorktreeCleanupMetadata
        )
    }

    func testPendingCleanupDoesNotRetryBranchAfterUncertainDeletionFailure() async throws {
        let state = try PendingBranchCleanupState(removalFailureCount: 0)
        defer { state.removeFiles() }
        let taskID = state.task.persistentModelID
        await state.fixture.worktreeManager.setListResult([
            WorktreeInfo(path: state.worktreeRoot.path, branch: state.branch, headOID: "owned-head")
        ])
        await state.fixture.worktreeManager.setDeleteBranchError(.deleteBranchFailed)

        do {
            try await state.fixture.viewModel.deleteThread(state.task)
            XCTFail("Expected the uncertain branch deletion failure")
        } catch let error as SidebarViewModelError {
            guard case .threadDeletePreparationFailed = error else {
                return XCTFail("Expected pre-commit cleanup failure, got \(error)")
            }
        }

        let retainedRun = try XCTUnwrap(state.fixture.context.resolveScheduledTaskRun(id: state.runID))
        XCTAssertEqual(retainedRun.pendingWorktreeCleanup?.branchIsOwned, false)
        XCTAssertEqual(retainedRun.pendingWorktreeCleanup?.branchOID, "owned-head")
        XCTAssertNotNil(state.fixture.context.resolveThread(id: taskID))

        await state.fixture.worktreeManager.setDeleteBranchError(nil)
        await state.fixture.worktreeManager.setListResult([])
        try await state.fixture.viewModel.deleteThread(state.task)

        let branchCalls = await state.fixture.worktreeManager.deleteBranchCalls()
        XCTAssertEqual(branchCalls.map(\.expectedOID), ["owned-head"])
        XCTAssertNil(state.fixture.context.resolveThread(id: taskID))
        XCTAssertFalse(
            try XCTUnwrap(state.fixture.context.resolveScheduledTaskRun(id: state.runID)).hasPendingWorktreeCleanupMetadata
        )
    }

    func testPendingCleanupWorktreeReplacementDuringListCannotPoisonBranchOID() async throws {
        let state = try PendingBranchReplacementState()
        defer { state.removeFiles() }
        await state.configureRace()

        do {
            try await state.fixture.viewModel.deleteThread(state.task)
            XCTFail("Expected the replacement-preserving cleanup failure")
        } catch let error as SidebarViewModelError {
            guard case .threadDeletePreparationFailed = error else {
                return XCTFail("Expected pre-commit cleanup failure, got \(error)")
            }
        }

        let retainedRun = try XCTUnwrap(state.fixture.context.resolveScheduledTaskRun(id: state.runID))
        let deleteBranchCalls = await state.fixture.worktreeManager.deleteBranchCalls()
        XCTAssertEqual(retainedRun.pendingWorktreeCleanup?.branchOID, "owned-head")
        XCTAssertTrue(retainedRun.pendingWorktreeCleanup?.branchIsOwned == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: state.replacementSentinel.path))
        XCTAssertTrue(deleteBranchCalls.isEmpty)
    }
}

@MainActor
private func rejectsOverlappingPendingCleanup(
    _ viewModel: SidebarViewModel,
    task: AgentThread,
    file: StaticString = #filePath,
    line: UInt = #line
) async -> Bool {
    do {
        try await viewModel.deleteThread(task)
        XCTFail("Expected overlapping pending cleanup to be rejected", file: file, line: line)
        return false
    } catch let error as SidebarViewModelError {
        guard case .threadDeletePreparationFailed(let underlying) = error,
              let cleanupError = underlying as? TaskWorkspaceCleanupError,
              case .pendingScheduledCleanupAlreadyInProgress = cleanupError else {
            XCTFail("Expected the in-progress cleanup error, got \(error)", file: file, line: line)
            return false
        }
        return true
    } catch {
        XCTFail("Expected a sidebar cleanup error, got \(error)", file: file, line: line)
        return false
    }
}

@MainActor
private struct PendingBranchReplacementState {
    let root: URL
    let worktreeRoot: URL
    let movedWorktreeRoot: URL
    let fixture: SidebarTestFixture
    let task: AgentThread
    let runID: PersistentIdentifier
    let branch = "alveary/list-replacement"

    var replacementSentinel: URL {
        worktreeRoot.appendingPathComponent("keep.txt")
    }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "alveary-pending-cleanup-list-replacement-\(UUID().uuidString)",
            isDirectory: true
        )
        let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
        worktreeRoot = root.appendingPathComponent("Worktree", isDirectory: true)
        movedWorktreeRoot = root.appendingPathComponent("MovedWorktree", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        let ownershipService = DefaultTaskWorkspaceOwnershipService(
            privateWorkspacesRoot: root.appendingPathComponent("Private", isDirectory: true),
            worktreeOwnershipRecordsRoot: root.appendingPathComponent("Records", isDirectory: true)
        )
        fixture = try SidebarTestFixture(taskWorkspaceOwnershipService: ownershipService)
        let workspace = try ownershipService.registerOwnedWorktree(
            at: worktreeRoot.path,
            sourceProjectPath: sourceRoot.path,
            grantedRoots: []
        )
        let run = makePendingBranchCleanupRun()
        run.setPendingWorktreeCleanup(try XCTUnwrap(ScheduledWorktreeCleanupProvenance(
            sourceProjectPath: sourceRoot.path,
            worktreePath: worktreeRoot.path,
            branch: branch,
            sourceProjectIdentity: ownershipService.directoryIdentity(at: sourceRoot.path),
            worktreeIdentity: ownershipService.directoryIdentity(at: worktreeRoot.path),
            branchIsOwned: true,
            branchOID: "owned-head",
            ownershipMarkerID: workspace.ownershipMarkerID,
            ownershipSourceProjectPath: workspace.sourceProjectPath
        )))
        task = makePendingBranchCleanupTask(run: run, conversationID: "pending-cleanup-list-replacement")
        fixture.context.insert(run)
        fixture.context.insert(task)
        try fixture.context.save()
        runID = run.persistentModelID
    }

    func configureRace() async {
        await fixture.worktreeManager.setListResult([
            WorktreeInfo(path: worktreeRoot.path, branch: branch, headOID: "poisoned-head")
        ])
        await fixture.worktreeManager.setValidatesRemovalIdentities(true)
        let worktreePath = worktreeRoot.path
        let movedWorktreePath = movedWorktreeRoot.path
        await fixture.worktreeManager.setListHook {
            try? FileManager.default.moveItem(atPath: worktreePath, toPath: movedWorktreePath)
            try? FileManager.default.createDirectory(atPath: worktreePath, withIntermediateDirectories: true)
            try? Data("keep".utf8).write(
                to: URL(fileURLWithPath: worktreePath).appendingPathComponent("keep.txt")
            )
        }
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private struct PendingBranchCleanupState {
    let root: URL
    let worktreeRoot: URL
    let fixture: SidebarTestFixture
    let task: AgentThread
    let runID: PersistentIdentifier
    let branch = "alveary/one-shot-cleanup"

    init(removalFailureCount: Int = 1) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-pending-cleanup-recreated-branch-\(UUID().uuidString)", isDirectory: true)
        let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
        worktreeRoot = root.appendingPathComponent("Worktree", isDirectory: true)
        let baseOwnershipService = DefaultTaskWorkspaceOwnershipService(
            privateWorkspacesRoot: root.appendingPathComponent("Private", isDirectory: true),
            worktreeOwnershipRecordsRoot: root.appendingPathComponent("Records", isDirectory: true)
        )
        let ownershipService = ScheduledMaterializerOwnershipService(
            base: baseOwnershipService,
            removalError: ScheduledMaterializerTestError.cleanupFailed,
            removalFailureCount: removalFailureCount
        )
        fixture = try SidebarTestFixture(taskWorkspaceOwnershipService: ownershipService)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        let workspace = try ownershipService.registerOwnedWorktree(
            at: worktreeRoot.path,
            sourceProjectPath: sourceRoot.path,
            grantedRoots: []
        )
        let run = makePendingBranchCleanupRun()
        run.setPendingWorktreeCleanup(try XCTUnwrap(ScheduledWorktreeCleanupProvenance(
            sourceProjectPath: sourceRoot.path,
            worktreePath: worktreeRoot.path,
            branch: branch,
            sourceProjectIdentity: ownershipService.directoryIdentity(at: sourceRoot.path),
            worktreeIdentity: ownershipService.directoryIdentity(at: worktreeRoot.path),
            ownershipMarkerID: workspace.ownershipMarkerID,
            ownershipSourceProjectPath: workspace.sourceProjectPath
        )))
        task = makePendingBranchCleanupTask(run: run, conversationID: "pending-cleanup-first-attempt")
        fixture.context.insert(run)
        fixture.context.insert(task)
        try fixture.context.save()
        runID = run.persistentModelID
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private func makePendingBranchCleanupRun() -> ScheduledTaskRun {
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
        workspaceKindSnapshot: .privateWorkspace,
        workspaceStrategySnapshot: .worktree
    )
}

@MainActor
private func makePendingBranchCleanupTask(
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

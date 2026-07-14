import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskRunRecoveryCoordinatorTests {
    func testRecoveryDoesNotExposeThreadlessWorkspaceWithCompletePendingCleanupMetadata() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let actionDate = Date(timeIntervalSinceReferenceDate: 5_999_800)
        let sourceIdentity = TaskWorkspaceFileSystemIdentity(systemNumber: 1, fileNumber: 48)
        let worktreeIdentity = TaskWorkspaceFileSystemIdentity(systemNumber: 1, fileNumber: 49)
        let workspace = TaskWorkspaceDescriptor(
            primaryRoot: "/tmp/threadless-pending-worktree",
            ownershipStrategy: .projectWorktreeOwned,
            ownershipMarkerID: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
            sourceProjectPath: "/tmp/threadless-pending-source"
        )
        let run = fixture.insertRun(status: .preparing, occurrenceAt: actionDate, withThread: false)
        try configurePendingCleanupRun(
            run,
            workspace: workspace,
            branch: "alveary/threadless-pending-cleanup",
            sourceIdentity: sourceIdentity,
            worktreeIdentity: worktreeIdentity
        )
        fixture.workspaceOwnershipService.setIdentity(
            sourceIdentity,
            at: try XCTUnwrap(workspace.sourceProjectPath)
        )
        fixture.workspaceOwnershipService.setIdentity(worktreeIdentity, at: workspace.primaryRoot)
        fixture.workspaceOwnershipService.allow(workspace, sourceProjectIdentity: sourceIdentity)
        try fixture.context.save()

        _ = try fixture.coordinator.recoverPersistedRuns(at: actionDate) { _ in false }

        XCTAssertEqual(run.status, .interrupted)
        XCTAssertNotNil(run.thread)
        XCTAssertNil(run.thread?.taskWorkspaceDescriptor)
        XCTAssertNil(run.thread?.worktreePath)
        XCTAssertNil(run.thread?.branch)
        XCTAssertFalse(run.thread?.useWorktree == true)
        XCTAssertNil(run.preparedWorkspaceRoot)
        XCTAssertNil(run.preparedWorkspaceOwnershipStrategy)
        XCTAssertNil(run.preparedWorkspaceMarkerID)
        XCTAssertEqual(run.pendingWorktreeCleanup?.worktreeIdentity, worktreeIdentity)
    }

    func testRecoveryDoesNotExposeThreadlessWorkspaceWithIncompletePendingCleanupMetadata() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let actionDate = Date(timeIntervalSinceReferenceDate: 5_999_900)
        let sourceIdentity = TaskWorkspaceFileSystemIdentity(systemNumber: 2, fileNumber: 58)
        let worktreeIdentity = TaskWorkspaceFileSystemIdentity(systemNumber: 2, fileNumber: 59)
        let workspace = TaskWorkspaceDescriptor(
            primaryRoot: "/tmp/threadless-incomplete-pending-worktree",
            ownershipStrategy: .projectWorktreeOwned,
            ownershipMarkerID: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
            sourceProjectPath: "/tmp/threadless-incomplete-pending-source"
        )
        let run = fixture.insertRun(status: .preparing, occurrenceAt: actionDate, withThread: false)
        try configurePendingCleanupRun(
            run,
            workspace: workspace,
            branch: "alveary/threadless-incomplete-pending-cleanup",
            sourceIdentity: sourceIdentity,
            worktreeIdentity: worktreeIdentity
        )
        run.pendingCleanupSourceIdentityFileNumber = nil
        fixture.workspaceOwnershipService.setIdentity(
            sourceIdentity,
            at: try XCTUnwrap(workspace.sourceProjectPath)
        )
        fixture.workspaceOwnershipService.setIdentity(worktreeIdentity, at: workspace.primaryRoot)
        fixture.workspaceOwnershipService.allow(workspace, sourceProjectIdentity: sourceIdentity)
        try fixture.context.save()

        _ = try fixture.coordinator.recoverPersistedRuns(at: actionDate) { _ in false }

        XCTAssertEqual(run.status, .interrupted)
        XCTAssertNotNil(run.thread)
        XCTAssertNil(run.pendingWorktreeCleanup)
        XCTAssertTrue(run.hasPendingWorktreeCleanupMetadata)
        XCTAssertNil(run.thread?.taskWorkspaceDescriptor)
        XCTAssertNil(run.thread?.worktreePath)
        XCTAssertNil(run.thread?.branch)
        XCTAssertFalse(run.thread?.useWorktree == true)
        XCTAssertEqual(run.preparedWorkspaceRoot, workspace.primaryRoot)
        XCTAssertEqual(run.preparedWorkspaceOwnershipStrategy, .projectWorktreeOwned)
        XCTAssertEqual(run.preparedWorkspaceMarkerID, workspace.ownershipMarkerID)
    }

    func testRecoveryMakesDescriptorAndPendingWorktreeCleanupDeletionSafe() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let actionDate = Date(timeIntervalSinceReferenceDate: 6_000_000)
        let sourcePath = "/tmp/pending-cleanup-source"
        let worktreePath = "/tmp/pending-cleanup-worktree"
        let branch = "alveary/pending-cleanup"
        let markerID = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
        let sourceIdentity = TaskWorkspaceFileSystemIdentity(systemNumber: 1, fileNumber: 50)
        let worktreeIdentity = TaskWorkspaceFileSystemIdentity(systemNumber: 1, fileNumber: 51)
        let workspace = TaskWorkspaceDescriptor(
            primaryRoot: worktreePath,
            ownershipStrategy: .projectWorktreeOwned,
            ownershipMarkerID: markerID,
            sourceProjectPath: sourcePath
        )
        let run = fixture.insertRun(status: .preparing, occurrenceAt: actionDate)
        try configurePendingCleanupRun(
            run,
            workspace: workspace,
            branch: branch,
            sourceIdentity: sourceIdentity,
            worktreeIdentity: worktreeIdentity
        )
        fixture.workspaceOwnershipService.setIdentity(sourceIdentity, at: sourcePath)
        fixture.workspaceOwnershipService.setIdentity(worktreeIdentity, at: worktreePath)
        fixture.workspaceOwnershipService.allow(workspace, sourceProjectIdentity: sourceIdentity)
        try fixture.context.save()

        _ = try fixture.coordinator.recoverPersistedRuns(at: actionDate) { _ in false }

        XCTAssertEqual(run.status, .interrupted)
        XCTAssertNil(run.thread?.taskWorkspaceDescriptor)
        XCTAssertNil(run.thread?.worktreePath)
        XCTAssertNil(run.thread?.branch)
        XCTAssertFalse(run.thread?.useWorktree == true)
        XCTAssertNil(run.preparedWorkspaceRoot)
        XCTAssertNil(run.preparedWorkspaceOwnershipStrategy)
        XCTAssertNil(run.preparedWorkspaceMarkerID)
        XCTAssertEqual(run.pendingWorktreeCleanup?.worktreeIdentity, worktreeIdentity)
    }

    func testRecoveryWithholdsWorkspaceForIncompletePendingCleanupMetadata() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let actionDate = Date(timeIntervalSinceReferenceDate: 6_000_100)
        let sourceIdentity = TaskWorkspaceFileSystemIdentity(systemNumber: 2, fileNumber: 60)
        let worktreeIdentity = TaskWorkspaceFileSystemIdentity(systemNumber: 2, fileNumber: 61)
        let workspace = TaskWorkspaceDescriptor(
            primaryRoot: "/tmp/incomplete-pending-worktree",
            ownershipStrategy: .projectWorktreeOwned,
            ownershipMarkerID: "ffffffff-ffff-4fff-8fff-ffffffffffff",
            sourceProjectPath: "/tmp/incomplete-pending-source"
        )
        let run = fixture.insertRun(status: .preparing, occurrenceAt: actionDate)
        try configurePendingCleanupRun(
            run,
            workspace: workspace,
            branch: "alveary/incomplete-pending-cleanup",
            sourceIdentity: sourceIdentity,
            worktreeIdentity: worktreeIdentity
        )
        run.pendingCleanupSourceIdentityFileNumber = nil
        try fixture.context.save()

        _ = try fixture.coordinator.recoverPersistedRuns(at: actionDate) { _ in false }

        XCTAssertEqual(run.status, .interrupted)
        XCTAssertNil(run.pendingWorktreeCleanup)
        XCTAssertTrue(run.hasPendingWorktreeCleanupMetadata)
        XCTAssertNil(run.thread?.taskWorkspaceDescriptor)
        XCTAssertNil(run.thread?.worktreePath)
        XCTAssertNil(run.thread?.branch)
        XCTAssertFalse(run.thread?.useWorktree == true)
        XCTAssertEqual(run.preparedWorkspaceRoot, workspace.primaryRoot)
        XCTAssertEqual(run.preparedWorkspaceOwnershipStrategy, .projectWorktreeOwned)
        XCTAssertEqual(run.preparedWorkspaceMarkerID, workspace.ownershipMarkerID)
    }
}

@MainActor
private extension ScheduledTaskRunRecoveryCoordinatorTests {
    func configurePendingCleanupRun(
        _ run: ScheduledTaskRun,
        workspace: TaskWorkspaceDescriptor,
        branch: String,
        sourceIdentity: TaskWorkspaceFileSystemIdentity,
        worktreeIdentity: TaskWorkspaceFileSystemIdentity
    ) throws {
        let sourceProjectPath = try XCTUnwrap(workspace.sourceProjectPath)
        run.workspaceKindRawValueSnapshot = ScheduledTaskWorkspaceKind.project.rawValue
        run.workspaceStrategyRawValueSnapshot = ScheduledTaskWorkspaceStrategy.worktree.rawValue
        run.projectPathSnapshot = sourceProjectPath
        run.workspaceIdentitySnapshot = ScheduledTaskWorkspaceIdentitySnapshot(
            projectRoot: ScheduledTaskRootIdentitySnapshot(path: sourceProjectPath, identity: sourceIdentity),
            grantedRoots: []
        )
        run.preparedWorkspaceRoot = workspace.primaryRoot
        run.preparedWorkspaceOwnershipStrategy = .projectWorktreeOwned
        run.preparedWorkspaceMarkerID = workspace.ownershipMarkerID
        run.thread?.taskWorkspaceDescriptor = workspace
        run.thread?.worktreePath = workspace.primaryRoot
        run.thread?.branch = branch
        run.thread?.useWorktree = true
        let provenance = try XCTUnwrap(ScheduledWorktreeCleanupProvenance(
            sourceProjectPath: sourceProjectPath,
            worktreePath: workspace.primaryRoot,
            branch: branch,
            sourceProjectIdentity: sourceIdentity,
            worktreeIdentity: worktreeIdentity,
            ownershipMarkerID: workspace.ownershipMarkerID,
            ownershipSourceProjectPath: sourceProjectPath
        ))
        run.setPendingWorktreeCleanup(provenance)
    }
}

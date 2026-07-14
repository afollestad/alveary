import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskRunMaterializerTests {
    func testProjectWorktreeIsRemovedWhenThreadPersistenceFails() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let projectRoot = try fixture.createDirectory(named: "Project")
        let worktreeRoot = try fixture.createDirectory(named: "Worktree")
        let expectedWorktreeIdentity = try fixture.workspaceOwnershipService.directoryIdentity(at: worktreeRoot.path)
        await fixture.worktreeManager.setCreateResult(
            WorktreeInfo(path: worktreeRoot.path, branch: "alveary/rollback")
        )
        let run = try fixture.insertRun(
            id: "worktree-failure",
            occurrenceID: "worktree-failure-occurrence",
            workspaceKind: .project,
            workspaceStrategy: .worktree,
            projectPath: projectRoot.path
        )
        var saveCount = 0
        let materializer = fixture.makeMaterializer(saveChanges: { context in
            saveCount += 1
            if saveCount == 5 {
                throw ScheduledMaterializerTestError.saveFailed
            }
            try context.save()
        })

        await XCTAssertThrowsErrorAsync {
            _ = try await materializer.materialize(runID: run.persistentModelID)
        }

        try await assertProjectWorktreeCleanup(
            fixture: fixture,
            run: run,
            projectRoot: projectRoot,
            worktreeRoot: worktreeRoot,
            expectedWorktreeIdentity: expectedWorktreeIdentity
        )
    }

    func testBranchDeletionFailureRetainsExactCleanupProvenanceForRetry() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let projectRoot = try fixture.createDirectory(named: "BranchRetryProject")
        let worktreeRoot = try fixture.createDirectory(named: "BranchRetryWorktree")
        await fixture.worktreeManager.setCreateResult(
            WorktreeInfo(path: worktreeRoot.path, branch: "alveary/branch-retry")
        )
        await fixture.worktreeManager.setRetryableDeleteBranchError(ScheduledMaterializerTestError.cleanupFailed)
        let run = try fixture.insertRun(
            id: "branch-delete-failure",
            occurrenceID: "branch-delete-failure-occurrence",
            workspaceKind: .project,
            workspaceStrategy: .worktree,
            projectPath: projectRoot.path
        )
        let runID = run.persistentModelID
        let probe = MaterializerBranchDeletionFenceProbe()
        let context = fixture.context
        await fixture.worktreeManager.setDeleteBranchHook {
            let pendingCleanup = context.resolveScheduledTaskRun(id: runID)?.pendingWorktreeCleanup
            probe.wasDurablyFencedBeforeDeletion = pendingCleanup?.branchIsOwned == false && !context.hasChanges
        }
        var saveCount = 0
        let materializer = fixture.makeMaterializer(saveChanges: { context in
            saveCount += 1
            if saveCount == 5 {
                throw ScheduledMaterializerTestError.saveFailed
            }
            try context.save()
        })

        await XCTAssertThrowsErrorAsync {
            _ = try await materializer.materialize(runID: run.persistentModelID)
        }

        let persistedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID))
        let cleanup = try XCTUnwrap(persistedRun.pendingWorktreeCleanup)
        XCTAssertTrue(cleanup.branchIsOwned)
        XCTAssertEqual(cleanup.branch, "alveary/branch-retry")
        XCTAssertEqual(cleanup.branchOID, "scheduled-head")
        XCTAssertTrue(probe.wasDurablyFencedBeforeDeletion)
        XCTAssertNil(cleanup.ownedWorkspaceDescriptor)
        XCTAssertNil(cleanup.worktreeIdentity)
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeRoot.path))
        let branchCalls = await fixture.worktreeManager.deleteBranchCalls()
        XCTAssertEqual(branchCalls.map(\.expectedOID), ["scheduled-head"])
    }

    func testRetirementPersistenceFailureRestoresOwnershipBeforeLaterFailureSave() throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let projectRoot = try fixture.createDirectory(named: "RetirementPersistenceProject")
        let worktreeRoot = try fixture.createDirectory(named: "RetirementPersistenceWorktree")
        let run = try fixture.insertRun(
            id: "retirement-persistence-failure",
            occurrenceID: "retirement-persistence-failure-occurrence",
            workspaceKind: .project,
            workspaceStrategy: .worktree,
            projectPath: projectRoot.path
        )
        let runID = run.persistentModelID
        try prepareTaskShell(fixture: fixture, runID: runID)
        let cleanup = try XCTUnwrap(ScheduledWorktreeCleanupProvenance(
            sourceProjectPath: projectRoot.path,
            worktreePath: worktreeRoot.path,
            branch: "alveary/retirement-persistence",
            sourceProjectIdentity: fixture.workspaceOwnershipService.directoryIdentity(at: projectRoot.path),
            worktreeIdentity: fixture.workspaceOwnershipService.directoryIdentity(at: worktreeRoot.path),
            branchIsOwned: true,
            branchOID: String(repeating: "a", count: 40),
            ownershipMarkerID: nil,
            ownershipSourceProjectPath: nil
        ))
        run.setPendingWorktreeCleanup(cleanup)
        try fixture.context.save()

        var saveCount = 0
        let materializer = fixture.makeMaterializer(
            saveChanges: { context in
                saveCount += 1
                if saveCount <= 2 {
                    throw ScheduledMaterializerTestError.saveFailed
                }
                try context.save()
            },
            provenancePersistenceAttempts: 2
        )

        XCTAssertThrowsError(
            try materializer.retirePendingWorktreeBranchOwnership(cleanup, runID: runID)
        )
        XCTAssertTrue(try XCTUnwrap(run.pendingWorktreeCleanup).branchIsOwned)

        try materializer.markTaskShellFailedWithRetry(
            runID: runID,
            error: ScheduledMaterializerTestError.cleanupFailed
        )

        let persistedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: runID))
        XCTAssertEqual(saveCount, 3)
        XCTAssertEqual(persistedRun.status, .failure)
        XCTAssertTrue(try XCTUnwrap(persistedRun.pendingWorktreeCleanup).branchIsOwned)
        XCTAssertFalse(fixture.context.hasChanges)
    }

    private func prepareTaskShell(
        fixture: ScheduledTaskRunMaterializerFixture,
        runID: PersistentIdentifier
    ) throws {
        let materializer = fixture.makeMaterializer()
        let snapshot = try materializer.transitionToPreparing(runID: runID)
        try materializer.persistTaskShellWithRetry(runID: runID, snapshot: snapshot)
    }

    private func assertProjectWorktreeCleanup(
        fixture: ScheduledTaskRunMaterializerFixture,
        run: ScheduledTaskRun,
        projectRoot: URL,
        worktreeRoot: URL,
        expectedWorktreeIdentity: TaskWorkspaceFileSystemIdentity
    ) async throws {
        let removeCalls = await fixture.worktreeManager.removeCalls()
        let removeProjectIdentities = await fixture.worktreeManager.removeProjectIdentities()
        let removeWorktreeIdentities = await fixture.worktreeManager.removeWorktreeIdentities()
        let deleteBranchCalls = await fixture.worktreeManager.deleteBranchCalls()
        XCTAssertEqual(
            removeCalls,
            [.init(projectPath: projectRoot.path, worktreePath: worktreeRoot.path, branch: nil)]
        )
        XCTAssertEqual(
            deleteBranchCalls,
            [.init(projectPath: projectRoot.path, branch: "alveary/rollback", expectedOID: "scheduled-head")]
        )
        XCTAssertEqual(
            removeProjectIdentities,
            [try XCTUnwrap(run.workspaceIdentitySnapshot?.projectRoot?.identity)]
        )
        XCTAssertEqual(removeWorktreeIdentities, [expectedWorktreeIdentity])
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeRoot.path))
        XCTAssertEqual(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID)?.status, .failure)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<AgentThread>()), 1)
        XCTAssertNil(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID)?.thread?.taskWorkspaceDescriptor)
    }
}

@MainActor
private final class MaterializerBranchDeletionFenceProbe {
    var wasDurablyFencedBeforeDeletion = false
}

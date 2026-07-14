import Foundation
import XCTest

@testable import Alveary

extension ScheduledMaterializerWorktreeManager {
    func create(
        projectPath: String,
        threadName: String,
        baseRef: String?,
        remoteName: String?,
        provenanceContext: WorktreeCreationProvenanceContext
    ) async throws -> IdentityValidatedWorktreeInfo {
        recordedCreateCalls.append(.init(
            projectPath: projectPath,
            threadName: threadName,
            baseRef: baseRef,
            remoteName: remoteName
        ))
        let expectedProjectIdentity = provenanceContext.expectedProjectIdentity
        recordedExpectedProjectIdentities.append(expectedProjectIdentity)
        if let createError {
            throw createError
        }
        try await recordProvenance(
            context: provenanceContext,
            projectPath: projectPath,
            worktreeIdentity: nil,
            branchIsOwned: false
        )
        let worktreeIdentity = try Self.directoryIdentity(at: createResult.path)
        try await recordProvenance(
            context: provenanceContext,
            projectPath: projectPath,
            worktreeIdentity: worktreeIdentity,
            branchIsOwned: false
        )
        try await recordProvenance(
            context: provenanceContext,
            projectPath: projectPath,
            worktreeIdentity: worktreeIdentity,
            branchIsOwned: true
        )
        createHook?()
        if cancelAfterCreate {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
        }
        return IdentityValidatedWorktreeInfo(
            info: createResult,
            sourceProjectIdentity: expectedProjectIdentity,
            worktreeIdentity: worktreeIdentity
        )
    }

    private func recordProvenance(
        context: WorktreeCreationProvenanceContext,
        projectPath: String,
        worktreeIdentity: TaskWorkspaceFileSystemIdentity?,
        branchIsOwned: Bool
    ) async throws {
        let cleanup = FailedWorktreeCreationCleanup(
            sourceProjectPath: projectPath,
            worktreePath: createResult.path,
            branch: createResult.branch,
            sourceProjectIdentity: context.expectedProjectIdentity,
            worktreeIdentity: worktreeIdentity,
            branchIsOwned: branchIsOwned,
            branchOID: branchIsOwned ? createResult.headOID : nil
        )
        try await context.recorder(cleanup)
        if let provenanceRecordHook {
            await provenanceRecordHook(cleanup)
        }
    }
}

@MainActor
extension ScheduledTaskRunMaterializerTests {
    func testCreationPersistsTargetIdentityBeforeBranchOwnershipIsRecorded() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let projectRoot = try fixture.createDirectory(named: "WriteAheadIdentityProject")
        let worktreeRoot = try fixture.createDirectory(named: "WriteAheadIdentityWorktree")
        let expectedIdentity = try fixture.workspaceOwnershipService.directoryIdentity(at: worktreeRoot.path)
        await fixture.worktreeManager.setCreateResult(
            WorktreeInfo(
                path: worktreeRoot.path,
                branch: "alveary/write-ahead-identity",
                headOID: "write-ahead-head"
            )
        )
        let run = try fixture.insertRun(
            id: "write-ahead-identity",
            occurrenceID: "write-ahead-identity-occurrence",
            workspaceKind: .project,
            workspaceStrategy: .worktree,
            projectPath: projectRoot.path
        )
        let runID = run.persistentModelID
        let context = fixture.context
        let probe = ScheduledWorktreeProvenanceProbe()
        await fixture.worktreeManager.setProvenanceRecordHook { cleanup in
            guard cleanup.worktreeIdentity != nil, !cleanup.branchIsOwned else {
                return
            }
            probe.didObserveIdentityStage = true
            probe.persistedIdentityAtIdentityStage = context
                .resolveScheduledTaskRun(id: runID)?
                .pendingWorktreeCleanup?
                .worktreeIdentity
        }

        _ = try await fixture.makeMaterializer().materialize(runID: runID)

        XCTAssertTrue(probe.didObserveIdentityStage)
        XCTAssertEqual(probe.persistedIdentityAtIdentityStage, expectedIdentity)
    }

    func testCleanupRetryCannotReclaimRetiredBranchOwnership() throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let sourceRoot = try fixture.createDirectory(named: "RetiredBranchSource")
        let worktreeRoot = try fixture.createDirectory(named: "RetiredBranchWorktree")
        let sourceIdentity = try fixture.workspaceOwnershipService.directoryIdentity(at: sourceRoot.path)
        let worktreeIdentity = try fixture.workspaceOwnershipService.directoryIdentity(at: worktreeRoot.path)
        let run = try fixture.insertRun(
            id: "retired-branch-retry",
            occurrenceID: "retired-branch-retry-occurrence"
        )
        run.status = .preparing
        let retired = try XCTUnwrap(ScheduledWorktreeCleanupProvenance(
            sourceProjectPath: sourceRoot.path,
            worktreePath: worktreeRoot.path,
            branch: "alveary/retired-branch",
            sourceProjectIdentity: sourceIdentity,
            worktreeIdentity: worktreeIdentity,
            branchIsOwned: false,
            branchOID: "retired-head",
            ownershipMarkerID: nil,
            ownershipSourceProjectPath: nil
        ))
        run.setPendingWorktreeCleanup(retired)
        try fixture.context.save()
        let staleRetry = try XCTUnwrap(ScheduledWorktreeCleanupProvenance(
            sourceProjectPath: sourceRoot.path,
            worktreePath: worktreeRoot.path,
            branch: "alveary/retired-branch",
            sourceProjectIdentity: sourceIdentity,
            worktreeIdentity: worktreeIdentity,
            branchIsOwned: true,
            branchOID: "replacement-head",
            ownershipMarkerID: nil,
            ownershipSourceProjectPath: nil
        ))

        let persisted = try fixture.makeMaterializer().persistPendingWorktreeCleanup(
            staleRetry,
            runID: run.persistentModelID
        )

        XCTAssertFalse(persisted.branchIsOwned)
        XCTAssertEqual(persisted.branchOID, "retired-head")
        XCTAssertEqual(run.pendingWorktreeCleanup, persisted)
    }

    func testSuccessfulBranchDeleteRetiresOwnershipBeforeWorkspaceCleanupRetry() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let sourceRoot = try fixture.createDirectory(named: "RetirementRetrySource")
        let worktreeRoot = try fixture.createDirectory(named: "RetirementRetryWorktree")
        let sourceIdentity = try fixture.workspaceOwnershipService.directoryIdentity(at: sourceRoot.path)
        let worktreeIdentity = try fixture.workspaceOwnershipService.directoryIdentity(at: worktreeRoot.path)
        let workspace = try fixture.workspaceOwnershipService.registerOwnedWorktree(
            at: worktreeRoot.path, sourceProjectPath: sourceRoot.path, grantedRoots: []
        )
        let run = try fixture.insertRun(id: "retirement-cleanup-retry", occurrenceID: "retirement-cleanup-retry-occurrence")
        run.status = .preparing
        let provenance = try XCTUnwrap(ScheduledWorktreeCleanupProvenance(
            sourceProjectPath: sourceRoot.path,
            worktreePath: worktreeRoot.path,
            branch: "alveary/retirement-retry",
            sourceProjectIdentity: sourceIdentity,
            worktreeIdentity: worktreeIdentity,
            branchIsOwned: true,
            branchOID: "owned-head",
            ownershipMarkerID: workspace.ownershipMarkerID,
            ownershipSourceProjectPath: workspace.sourceProjectPath
        ))
        run.setPendingWorktreeCleanup(provenance)
        try fixture.context.save()
        let ownershipService = ScheduledMaterializerOwnershipService(
            base: fixture.workspaceOwnershipService, removalError: ScheduledMaterializerTestError.cleanupFailed, removalFailureCount: 1
        )
        let materializer = fixture.makeMaterializer(ownershipService: ownershipService)

        await XCTAssertThrowsErrorAsync {
            try await materializer.cleanupWorktree(runID: run.persistentModelID, provenance: provenance, registeredWorkspace: workspace)
        }

        let retiredCleanup = try XCTUnwrap(run.pendingWorktreeCleanup)
        XCTAssertFalse(retiredCleanup.branchIsOwned)
        XCTAssertEqual(retiredCleanup.branchOID, "owned-head")
        XCTAssertEqual(retiredCleanup.sourceProjectIdentity, sourceIdentity)
        XCTAssertNotNil(retiredCleanup.ownedWorkspaceDescriptor)

        try await materializer.cleanupWorktree(runID: run.persistentModelID, provenance: provenance, registeredWorkspace: workspace)

        let branchCalls = await fixture.worktreeManager.deleteBranchCalls()
        XCTAssertEqual(branchCalls.map(\.expectedOID), ["owned-head"])
        XCTAssertFalse(run.hasPendingWorktreeCleanupMetadata)
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeRoot.path))
    }

    func testUncertainBranchDeleteRetiresOwnershipAndRetrySkipsBranch() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let sourceRoot = try fixture.createDirectory(named: "UncertainDeleteSource")
        let worktreeRoot = try fixture.createDirectory(named: "UncertainDeleteWorktree")
        let sourceIdentity = try fixture.workspaceOwnershipService.directoryIdentity(at: sourceRoot.path)
        let worktreeIdentity = try fixture.workspaceOwnershipService.directoryIdentity(at: worktreeRoot.path)
        let workspace = try fixture.workspaceOwnershipService.registerOwnedWorktree(
            at: worktreeRoot.path, sourceProjectPath: sourceRoot.path, grantedRoots: []
        )
        await fixture.worktreeManager.setCreateResult(WorktreeInfo(
            path: worktreeRoot.path, branch: "alveary/uncertain-delete", headOID: "uncertain-head"
        ))
        let run = try fixture.insertRun(id: "uncertain-delete", occurrenceID: "uncertain-delete-occurrence")
        run.status = .preparing
        let provenance = try XCTUnwrap(ScheduledWorktreeCleanupProvenance(
            sourceProjectPath: sourceRoot.path,
            worktreePath: worktreeRoot.path,
            branch: "alveary/uncertain-delete",
            sourceProjectIdentity: sourceIdentity,
            worktreeIdentity: worktreeIdentity,
            branchIsOwned: true,
            branchOID: "uncertain-head",
            ownershipMarkerID: workspace.ownershipMarkerID,
            ownershipSourceProjectPath: workspace.sourceProjectPath
        ))
        run.setPendingWorktreeCleanup(provenance)
        try fixture.context.save()
        await fixture.worktreeManager.setDeleteBranchError(ScheduledMaterializerTestError.cleanupFailed)
        let materializer = fixture.makeMaterializer()

        do {
            try await materializer.cleanupWorktree(runID: run.persistentModelID, provenance: provenance, registeredWorkspace: workspace)
            XCTFail("Expected uncertain branch deletion to fail cleanup.")
        } catch ScheduledMaterializerTestError.cleanupFailed {
            // The verbatim generic error represents an outcome that cannot safely be retried.
        } catch {
            XCTFail("Expected the configured branch deletion error, got \(error).")
        }

        let retiredCleanup = try XCTUnwrap(run.pendingWorktreeCleanup)
        XCTAssertFalse(retiredCleanup.branchIsOwned)
        XCTAssertEqual(retiredCleanup.branchOID, "uncertain-head")
        XCTAssertNil(retiredCleanup.ownedWorkspaceDescriptor)
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeRoot.path))
        await fixture.worktreeManager.setDeleteBranchError(nil)

        try await materializer.cleanupWorktree(runID: run.persistentModelID, provenance: provenance, registeredWorkspace: nil)

        let branchCalls = await fixture.worktreeManager.deleteBranchCalls()
        XCTAssertEqual(branchCalls.map(\.expectedOID), ["uncertain-head"])
        XCTAssertFalse(run.hasPendingWorktreeCleanupMetadata)
    }
}

@MainActor
private final class ScheduledWorktreeProvenanceProbe {
    var didObserveIdentityStage = false
    var persistedIdentityAtIdentityStage: TaskWorkspaceFileSystemIdentity?
}

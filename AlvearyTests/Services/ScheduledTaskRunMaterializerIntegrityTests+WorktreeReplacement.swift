import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskRunMaterializerTests {
    func testWorktreeReplacementAfterCreateIsNotRegisteredOrRemoved() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let projectRoot = try fixture.createDirectory(named: "ReplacementRaceProject")
        let worktreeRoot = try fixture.createDirectory(named: "ReplacementRaceWorktree")
        let movedWorktreeRoot = fixture.root.appendingPathComponent("MovedReplacementRaceWorktree", isDirectory: true)
        let originalWorktreeIdentity = try fixture.workspaceOwnershipService.directoryIdentity(at: worktreeRoot.path)
        await fixture.worktreeManager.setCreateResult(
            WorktreeInfo(path: worktreeRoot.path, branch: "alveary/replacement-race")
        )
        let worktreePath = worktreeRoot.path
        let movedWorktreePath = movedWorktreeRoot.path
        await fixture.worktreeManager.setCreateHook {
            try? FileManager.default.moveItem(atPath: worktreePath, toPath: movedWorktreePath)
            try? FileManager.default.createDirectory(atPath: worktreePath, withIntermediateDirectories: true)
            try? Data("keep".utf8).write(
                to: URL(fileURLWithPath: worktreePath).appendingPathComponent("keep.txt")
            )
        }
        let run = try fixture.insertRun(
            id: "worktree-replacement-race",
            occurrenceID: "worktree-replacement-race-occurrence",
            workspaceKind: .project,
            workspaceStrategy: .worktree,
            projectPath: projectRoot.path
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.makeMaterializer().materialize(runID: run.persistentModelID)
        }

        let persistedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID))
        let pendingCleanup = try XCTUnwrap(persistedRun.pendingWorktreeCleanup)
        let expectedProjectIdentity = try XCTUnwrap(run.workspaceIdentitySnapshot?.projectRoot?.identity)
        let createProjectIdentities = await fixture.worktreeManager.expectedProjectIdentities()
        let removeCalls = await fixture.worktreeManager.removeCalls()
        XCTAssertEqual(persistedRun.status, .failure)
        XCTAssertTrue(try XCTUnwrap(persistedRun.lastError).contains("workspace cleanup also failed"))
        XCTAssertNil(persistedRun.thread?.taskWorkspaceDescriptor)
        XCTAssertEqual(pendingCleanup.worktreeIdentity, originalWorktreeIdentity)
        XCTAssertNotNil(pendingCleanup.ownedWorkspaceDescriptor)
        XCTAssertTrue(pendingCleanup.branchIsOwned)
        XCTAssertTrue(FileManager.default.fileExists(atPath: worktreeRoot.appendingPathComponent("keep.txt").path))
        let recordsRoot = fixture.root.appendingPathComponent("WorktreeRecords", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordsRoot.path))
        XCTAssertEqual(createProjectIdentities, [expectedProjectIdentity])
        XCTAssertTrue(removeCalls.isEmpty)
    }

    func testWorktreeGrantSamePathReplacementAfterCreateIsRejectedAndCleanedUp() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let projectRoot = try fixture.createDirectory(named: "GrantReplacementProject")
        let grantRoot = try fixture.createDirectory(named: "GrantToReplaceAfterCreate")
        let worktreeRoot = try fixture.createDirectory(named: "GrantReplacementWorktree")
        await fixture.worktreeManager.setCreateResult(
            WorktreeInfo(path: worktreeRoot.path, branch: "alveary/grant-replacement")
        )
        let grantPath = grantRoot.path
        await fixture.worktreeManager.setCreateHook {
            try? FileManager.default.removeItem(atPath: grantPath)
            try? FileManager.default.createDirectory(
                atPath: grantPath,
                withIntermediateDirectories: true
            )
            try? Data("keep".utf8).write(
                to: URL(fileURLWithPath: grantPath).appendingPathComponent("keep.txt")
            )
        }
        let run = try fixture.insertRun(
            id: "worktree-grant-replacement",
            occurrenceID: "worktree-grant-replacement-occurrence",
            workspaceKind: .project,
            workspaceStrategy: .worktree,
            projectPath: projectRoot.path,
            grantedRoots: [grantPath]
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.makeMaterializer().materialize(runID: run.persistentModelID)
        }

        try await assertGrantReplacementCleanup(
            fixture: fixture,
            runID: run.persistentModelID,
            projectRoot: projectRoot,
            grantPath: grantPath,
            worktreeRoot: worktreeRoot
        )
    }

    func testWorktreeReplacementDuringCleanupListCannotPoisonDurableBranchOID() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let projectRoot = try fixture.createDirectory(named: "CleanupListReplacementProject")
        let grantRoot = try fixture.createDirectory(named: "CleanupListReplacementGrant")
        let worktreeRoot = try fixture.createDirectory(named: "CleanupListReplacementWorktree")
        let movedWorktreeRoot = fixture.root.appendingPathComponent(
            "MovedCleanupListReplacementWorktree",
            isDirectory: true
        )
        let branch = "alveary/cleanup-list-replacement"
        await fixture.worktreeManager.setCreateResult(
            WorktreeInfo(path: worktreeRoot.path, branch: branch, headOID: "owned-head")
        )
        await fixture.worktreeManager.setListResult([
            WorktreeInfo(path: worktreeRoot.path, branch: branch, headOID: "poisoned-head")
        ])
        let grantPath = grantRoot.path
        await fixture.worktreeManager.setCreateHook {
            try? FileManager.default.removeItem(atPath: grantPath)
            try? FileManager.default.createDirectory(atPath: grantPath, withIntermediateDirectories: true)
        }
        let worktreePath = worktreeRoot.path
        let movedWorktreePath = movedWorktreeRoot.path
        await fixture.worktreeManager.setListHook {
            try? FileManager.default.moveItem(atPath: worktreePath, toPath: movedWorktreePath)
            try? FileManager.default.createDirectory(atPath: worktreePath, withIntermediateDirectories: true)
            try? Data("keep".utf8).write(
                to: URL(fileURLWithPath: worktreePath).appendingPathComponent("keep.txt")
            )
        }
        let run = try fixture.insertRun(
            id: "cleanup-list-replacement",
            occurrenceID: "cleanup-list-replacement-occurrence",
            workspaceKind: .project,
            workspaceStrategy: .worktree,
            projectPath: projectRoot.path,
            grantedRoots: [grantRoot.path]
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.makeMaterializer().materialize(runID: run.persistentModelID)
        }

        let persistedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID))
        let deleteBranchCalls = await fixture.worktreeManager.deleteBranchCalls()
        XCTAssertEqual(persistedRun.pendingWorktreeCleanup?.branchOID, "owned-head")
        XCTAssertTrue(persistedRun.pendingWorktreeCleanup?.branchIsOwned == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: worktreeRoot.appendingPathComponent("keep.txt").path))
        XCTAssertTrue(deleteBranchCalls.isEmpty)
    }

    private func assertGrantReplacementCleanup(
        fixture: ScheduledTaskRunMaterializerFixture,
        runID: PersistentIdentifier,
        projectRoot: URL,
        grantPath: String,
        worktreeRoot: URL
    ) async throws {
        let persistedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: runID))
        XCTAssertEqual(persistedRun.status, .failure)
        XCTAssertEqual(persistedRun.lastError, ScheduledTaskRunMaterializationError.workspaceRootsChanged.localizedDescription)
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeRoot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: grantPath).appendingPathComponent("keep.txt").path))
        let removeCalls = await fixture.worktreeManager.removeCalls()
        let deleteBranchCalls = await fixture.worktreeManager.deleteBranchCalls()
        XCTAssertEqual(
            removeCalls,
            [.init(
                projectPath: projectRoot.path,
                worktreePath: worktreeRoot.path,
                branch: nil
            )]
        )
        XCTAssertEqual(
            deleteBranchCalls,
            [
                .init(
                    projectPath: projectRoot.path,
                    branch: "alveary/grant-replacement",
                    expectedOID: "scheduled-head"
                )
            ]
        )
    }
}

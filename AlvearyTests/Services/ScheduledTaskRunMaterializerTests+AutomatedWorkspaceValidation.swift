import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskRunMaterializerTests {
    func testAutomatedWorkspaceValidationRejectsADifferentOwnedWorkspace() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let run = try fixture.insertRun(
            id: "owned-workspace-replacement",
            occurrenceID: "owned-workspace-replacement-occurrence"
        )
        _ = try await fixture.makeMaterializer().materialize(runID: run.persistentModelID)
        let persistedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID))
        let thread = try XCTUnwrap(persistedRun.thread)
        let replacement = try fixture.workspaceOwnershipService.createPrivateWorkspace()
        thread.taskWorkspaceDescriptor = replacement

        XCTAssertThrowsError(
            try ScheduledTaskAutomatedWorkspaceValidator(
                workspaceOwnershipService: fixture.workspaceOwnershipService
            ).validate(thread: thread)
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                ScheduledTurnWorkspaceValidationError.workspaceDoesNotMatchRun.localizedDescription
            )
        }
    }

    func testAutomatedWorkspaceValidationRejectsSamePathSourceReplacement() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let materialized = try await materializeOwnedWorktree(
            fixture: fixture,
            id: "automated-source-replacement"
        )
        let expectedIdentity = try XCTUnwrap(
            fixture.workspaceOwnershipService.sourceProjectIdentity(forOwnedWorktree: materialized.workspace)
        )
        try FileManager.default.removeItem(at: materialized.projectRoot)
        try FileManager.default.createDirectory(at: materialized.projectRoot, withIntermediateDirectories: true)
        XCTAssertNotEqual(
            try fixture.workspaceOwnershipService.directoryIdentity(at: materialized.projectRoot.path),
            expectedIdentity
        )

        assertAutomatedWorkspaceValidationRejected(
            thread: materialized.thread,
            ownershipService: fixture.workspaceOwnershipService
        )
    }

    func testAutomatedWorkspaceValidationRejectsCanonicalSourceAlias() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let materialized = try await materializeOwnedWorktree(
            fixture: fixture,
            id: "automated-source-alias"
        )
        let expectedIdentity = try XCTUnwrap(
            fixture.workspaceOwnershipService.sourceProjectIdentity(forOwnedWorktree: materialized.workspace)
        )
        let movedSource = fixture.root.appendingPathComponent("MovedAutomatedSource", isDirectory: true)
        try FileManager.default.moveItem(at: materialized.projectRoot, to: movedSource)
        try FileManager.default.createSymbolicLink(
            atPath: materialized.projectRoot.path,
            withDestinationPath: movedSource.path
        )
        let aliasFollowingOwnershipService = ScheduledMaterializerOwnershipService(
            base: fixture.workspaceOwnershipService,
            followsCanonicalDirectoryIdentity: true
        )
        XCTAssertEqual(
            try aliasFollowingOwnershipService.directoryIdentity(at: materialized.projectRoot.path),
            expectedIdentity
        )
        XCTAssertNotEqual(CanonicalPath.normalize(materialized.projectRoot.path), materialized.projectRoot.path)

        assertAutomatedWorkspaceValidationRejected(
            thread: materialized.thread,
            ownershipService: aliasFollowingOwnershipService
        )
    }

    private func materializeOwnedWorktree(
        fixture: ScheduledTaskRunMaterializerFixture,
        id: String
    ) async throws -> MaterializedOwnedWorktree {
        let projectRoot = try fixture.createDirectory(named: "\(id)-project")
        let worktreeRoot = try fixture.createDirectory(named: "\(id)-worktree")
        await fixture.worktreeManager.setCreateResult(
            WorktreeInfo(path: worktreeRoot.path, branch: "alveary/\(id)")
        )
        let run = try fixture.insertRun(
            id: id,
            occurrenceID: "\(id)-occurrence",
            workspaceKind: .project,
            workspaceStrategy: .worktree,
            projectPath: projectRoot.path
        )
        let materialization = try await fixture.makeMaterializer().materialize(runID: run.persistentModelID)
        let thread = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID)?.thread)
        return MaterializedOwnedWorktree(
            projectRoot: projectRoot,
            workspace: materialization.workspace,
            thread: thread
        )
    }

    private func assertAutomatedWorkspaceValidationRejected(
        thread: AgentThread,
        ownershipService: any TaskWorkspaceOwnershipService
    ) {
        XCTAssertThrowsError(
            try ScheduledTaskAutomatedWorkspaceValidator(
                workspaceOwnershipService: ownershipService
            ).validate(thread: thread)
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                ScheduledTurnWorkspaceValidationError.workspaceRootsChanged.localizedDescription
            )
        }
    }
}

@MainActor
private struct MaterializedOwnedWorktree {
    let projectRoot: URL
    let workspace: TaskWorkspaceDescriptor
    let thread: AgentThread
}

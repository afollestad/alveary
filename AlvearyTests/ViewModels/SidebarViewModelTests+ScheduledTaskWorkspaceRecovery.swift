import Foundation
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    // swiftlint:disable:next function_body_length
    func testProjectDeletionUsesDurableScheduledWorktreeCleanupProvenance() async throws {
        let fixture = try SidebarTestFixture()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-project-scheduled-worktree-\(UUID().uuidString)", isDirectory: true)
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
        let branch = "alveary/scheduled-project"
        let currentHead = "current-scheduled-head"
        let cleanup = try XCTUnwrap(ScheduledWorktreeCleanupProvenance(
            sourceProjectPath: sourceRoot.path,
            worktreePath: worktreeRoot.path,
            branch: branch,
            sourceProjectIdentity: sourceIdentity,
            worktreeIdentity: worktreeIdentity,
            branchIsOwned: true,
            branchOID: "initial-head",
            ownershipMarkerID: workspace.ownershipMarkerID,
            ownershipSourceProjectPath: workspace.sourceProjectPath
        ))
        let project = Project(path: sourceRoot.path, name: "Scheduled source")
        let run = ScheduledTaskRun(
            occurrenceID: UUID().uuidString,
            definitionID: "scheduled-project-definition",
            definitionRevision: 1,
            occurrenceAt: Date(timeIntervalSince1970: 1_800_000_000),
            triggerKind: .scheduled,
            status: .success,
            titleSnapshot: "Scheduled task",
            promptSnapshot: "Run scheduled work.",
            timeZoneIdentifierSnapshot: "America/Chicago",
            providerIDSnapshot: "codex",
            effortSnapshot: "high",
            permissionModeSnapshot: "default",
            workspaceKindSnapshot: .project,
            workspaceStrategySnapshot: .worktree,
            projectPathSnapshot: sourceRoot.path,
            workspaceCleanupProvenance: cleanup,
            preparedWorkspaceRoot: worktreeRoot.path,
            preparedWorkspaceOwnershipStrategy: .projectWorktreeOwned,
            preparedWorkspaceMarkerID: workspace.ownershipMarkerID
        )
        let thread = AgentThread(
            name: "Scheduled project thread",
            branch: branch,
            worktreePath: worktreeRoot.path,
            useWorktree: true,
            mode: .project,
            project: project,
            scheduledTaskRun: run
        )
        thread.taskWorkspaceDescriptor = workspace
        thread.conversations = [Conversation(id: "scheduled-project-main", provider: "codex", thread: thread)]
        project.threads = [thread]
        run.thread = thread
        fixture.context.insert(project)
        fixture.context.insert(run)
        try fixture.context.save()
        let projectID = project.persistentModelID
        let threadID = thread.persistentModelID
        let runID = run.persistentModelID
        await fixture.worktreeManager.setValidatesRemovalIdentities(true)
        await fixture.worktreeManager.setListResult([
            WorktreeInfo(path: worktreeRoot.path, branch: branch, headOID: currentHead)
        ])

        let currentProject = try XCTUnwrap(fixture.context.resolveProject(id: projectID))
        try await fixture.viewModel.deleteProject(currentProject)

        XCTAssertNil(fixture.context.resolveThread(id: threadID))
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeRoot.path))
        let removeCalls = await fixture.worktreeManager.removeCalls()
        let removeCall = try XCTUnwrap(removeCalls.first)
        XCTAssertNil(removeCall.branch)
        let branchCalls = await fixture.worktreeManager.deleteBranchCalls()
        let branchCall = try XCTUnwrap(branchCalls.first)
        XCTAssertEqual(branchCall.expectedOID, currentHead)
        let retainedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: runID))
        XCTAssertNil(retainedRun.workspaceCleanupProvenance)
        XCTAssertNil(retainedRun.pendingWorktreeCleanup)
    }

    func testDeleteOwnedTaskWorktreeRejectsCanonicalSourceAlias() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-task-source-alias-\(UUID().uuidString)", isDirectory: true)
        let baseOwnershipService = DefaultTaskWorkspaceOwnershipService(
            privateWorkspacesRoot: root.appendingPathComponent("Private", isDirectory: true),
            worktreeOwnershipRecordsRoot: root.appendingPathComponent("Records", isDirectory: true)
        )
        let ownershipService = ScheduledMaterializerOwnershipService(
            base: baseOwnershipService,
            followsCanonicalDirectoryIdentity: true
        )
        let fixture = try SidebarTestFixture(taskWorkspaceOwnershipService: ownershipService)
        let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
        let movedSourceRoot = root.appendingPathComponent("MovedSource", isDirectory: true)
        let worktreeRoot = root.appendingPathComponent("Worktree", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try fixture.taskWorkspaceOwnershipService.registerOwnedWorktree(
            at: worktreeRoot.path,
            sourceProjectPath: sourceRoot.path,
            grantedRoots: []
        )
        try FileManager.default.moveItem(at: sourceRoot, to: movedSourceRoot)
        try FileManager.default.createSymbolicLink(
            atPath: sourceRoot.path,
            withDestinationPath: movedSourceRoot.path
        )
        let sentinel = movedSourceRoot.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinel)
        await fixture.worktreeManager.setListResult([
            WorktreeInfo(path: worktreeRoot.path, branch: "alveary/source-alias")
        ])
        let task = makeRecoveredWorktreeTask(
            workspace: workspace,
            branch: "alveary/source-alias",
            conversationID: "source-alias-task"
        )
        fixture.context.insert(task)
        try fixture.context.save()

        try await fixture.viewModel.deleteThread(task)

        let removeCalls = await fixture.worktreeManager.removeCalls()
        let branchCalls = await fixture.worktreeManager.deleteBranchCalls()
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeRoot.path))
        XCTAssertTrue(removeCalls.isEmpty)
        XCTAssertTrue(branchCalls.isEmpty)
        XCTAssertNoThrow(try fixture.taskWorkspaceOwnershipService.removeOwnedWorkspace(workspace))
    }

    func testDeleteRecoveredWorktreePreservesRegisteredBranchWhenThreadBranchIsMissing() async throws {
        let fixture = try SidebarTestFixture()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-recovered-worktree-\(UUID().uuidString)", isDirectory: true)
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
        let registeredBranch = "alveary/recovered-branch"
        await fixture.worktreeManager.setListResult([
            WorktreeInfo(path: worktreeRoot.path, branch: registeredBranch)
        ])
        let task = makeRecoveredWorktreeTask(
            workspace: workspace,
            branch: nil,
            conversationID: "recovered-worktree-task"
        )
        fixture.context.insert(task)
        try fixture.context.save()

        try await fixture.viewModel.deleteThread(task)

        let removeCalls = await fixture.worktreeManager.removeCalls()
        let removeCall = try XCTUnwrap(removeCalls.first)
        XCTAssertEqual(removeCall.projectPath, sourceRoot.path)
        XCTAssertEqual(removeCall.worktreePath, worktreeRoot.path)
        XCTAssertNil(removeCall.branch)
    }

    func testDeleteOwnedTaskWorktreePreservesPersonalBranchAfterUserSwitch() async throws {
        let fixture = try SidebarTestFixture()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-switched-task-worktree-\(UUID().uuidString)", isDirectory: true)
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
        await fixture.worktreeManager.setListResult([
            WorktreeInfo(path: worktreeRoot.path, branch: "user/personal-work")
        ])
        let task = makeRecoveredWorktreeTask(
            workspace: workspace,
            branch: "alveary/original-task-branch",
            conversationID: "switched-worktree-task"
        )
        fixture.context.insert(task)
        try fixture.context.save()

        try await fixture.viewModel.deleteThread(task)

        let removeCalls = await fixture.worktreeManager.removeCalls()
        let branchCalls = await fixture.worktreeManager.deleteBranchCalls()
        let removeCall = try XCTUnwrap(removeCalls.first)
        XCTAssertEqual(removeCall.projectPath, sourceRoot.path)
        XCTAssertEqual(removeCall.worktreePath, worktreeRoot.path)
        XCTAssertNil(removeCall.branch)
        XCTAssertTrue(branchCalls.isEmpty)
    }

    func testDeleteTerminalScheduledTaskUsesPreparedPrivateCleanupWhenThreadWorkspaceWasWithheld() async throws {
        let fixture = try SidebarTestFixture()
        let workspace = try fixture.taskWorkspaceOwnershipService.createPrivateWorkspace()
        let run = makeRecoveredScheduledRun(status: .failure)
        run.preparedWorkspaceRoot = workspace.primaryRoot
        run.preparedWorkspaceOwnershipStrategy = .privateOwned
        run.preparedWorkspaceMarkerID = workspace.ownershipMarkerID
        let task = AgentThread(
            name: "Failed scheduled task",
            mode: .task,
            scheduledTaskRun: run
        )
        task.conversations = [
            Conversation(id: "retained-private-workspace", provider: "codex", thread: task)
        ]
        run.thread = task
        fixture.context.insert(run)
        fixture.context.insert(task)
        try fixture.context.save()

        try await fixture.viewModel.deleteThread(task)

        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.primaryRoot))
        XCTAssertNil(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID)?.thread)
    }
}

@MainActor
private func makeRecoveredWorktreeTask(
    workspace: TaskWorkspaceDescriptor,
    branch: String?,
    conversationID: String
) -> AgentThread {
    let task = AgentThread(
        name: "Recovered scheduled task",
        branch: branch,
        worktreePath: workspace.primaryRoot,
        useWorktree: true,
        mode: .task,
        taskWorkspaceDescriptor: workspace
    )
    task.conversations = [Conversation(id: conversationID, provider: "codex", thread: task)]
    return task
}

@MainActor
private func makeRecoveredScheduledRun(status: ScheduledTaskRunStatus) -> ScheduledTaskRun {
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

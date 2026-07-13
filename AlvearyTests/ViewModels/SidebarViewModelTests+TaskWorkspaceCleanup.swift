import Foundation
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
        XCTAssertTrue(branchCalls.isEmpty)
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
}

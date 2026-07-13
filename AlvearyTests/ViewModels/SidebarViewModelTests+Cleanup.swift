import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testArchiveThreadInvalidatesEveryConversationController() async throws {
        let invalidations = SidebarControllerInvalidationRecorder()
        let fixture = try SidebarTestFixture(
            invalidateConversationController: invalidations.record
        )
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-archive-controller-cleanup",
            conversationIDs: ["main", "side"]
        )

        try await fixture.viewModel.archiveThread(thread)

        XCTAssertEqual(invalidations.conversationIDs.sorted(), ["main", "side"])
    }

    func testDeletionSaveFailureKeepsTargetAndPersistsUnrelatedPendingChange() async throws {
        let fixture = try SidebarTestFixture(saveDeletionCommit: { _ in
            throw SidebarDeletionCommitTestError.saveFailed
        })
        let thread = try fixture.insertThread(
            projectName: "Deleted target",
            projectPath: "/tmp/deletion-save-target",
            conversationIDs: ["main"]
        )
        let unrelatedProject = try fixture.insertProject(
            name: "Original name",
            path: "/tmp/deletion-save-unrelated"
        )
        unrelatedProject.name = "Persisted pending name"

        do {
            try await fixture.viewModel.deleteThread(thread)
            XCTFail("Expected deletion commit to fail")
        } catch SidebarDeletionCommitTestError.saveFailed {
            // expected
        }

        XCTAssertNotNil(fixture.context.resolveThread(id: thread.persistentModelID))
        let verificationContext = ModelContext(fixture.container)
        let unrelatedPath = unrelatedProject.path
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { project in
            project.path == unrelatedPath
        })
        XCTAssertEqual(try verificationContext.fetch(descriptor).first?.name, "Persisted pending name")
        let removedConversationIDs = await fixture.attachmentStore.removedConversationIDs
        XCTAssertTrue(removedConversationIDs.isEmpty)
    }

    func testDeleteThreadRemovesEveryConversationAttachmentDirectory() async throws {
        let invalidations = SidebarControllerInvalidationRecorder()
        let fixture = try SidebarTestFixture(
            invalidateConversationController: invalidations.record
        )
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-attachment-cleanup",
            conversationIDs: ["main", "side"]
        )

        try await fixture.viewModel.deleteThread(thread)

        let removedConversationIDs = await fixture.attachmentStore.removedConversationIDs
        XCTAssertEqual(removedConversationIDs.sorted(), ["main", "side"])
        XCTAssertEqual(invalidations.conversationIDs.sorted(), ["main", "side"])
    }

    func testDeleteTaskRemovesOwnedPrivateWorkspaceButPreservesGrants() async throws {
        let fixture = try SidebarTestFixture()
        let task = try await fixture.viewModel.openTaskDraft()
        let originalWorkspace = try XCTUnwrap(task.taskWorkspaceDescriptor)
        let grantedRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-task-delete-grant-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: grantedRoot, withIntermediateDirectories: true)
        task.taskWorkspaceDescriptor = TaskWorkspaceDescriptor(
            primaryRoot: originalWorkspace.primaryRoot,
            grantedRoots: [grantedRoot.path],
            ownershipStrategy: originalWorkspace.ownershipStrategy,
            ownershipMarkerID: originalWorkspace.ownershipMarkerID
        )
        task.isDraft = false
        try fixture.context.save()
        let taskID = task.persistentModelID

        try await fixture.viewModel.deleteThread(task)

        XCTAssertNil(fixture.context.resolveThread(id: taskID))
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalWorkspace.primaryRoot))
        XCTAssertTrue(FileManager.default.fileExists(atPath: grantedRoot.path))
        try? FileManager.default.removeItem(at: grantedRoot)
    }

    func testDeleteTaskRemovesOwnedWorktreeThroughSourceProject() async throws {
        let fixture = try SidebarTestFixture()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-task-worktree-delete-\(UUID().uuidString)", isDirectory: true)
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
            name: "Worktree task",
            branch: "alveary/task-run",
            mode: .task,
            taskWorkspaceDescriptor: workspace
        )
        task.conversations = [Conversation(id: "worktree-task", provider: "codex", thread: task)]
        fixture.context.insert(task)
        try fixture.context.save()
        await fixture.worktreeManager.setListResult([
            WorktreeInfo(path: worktreeRoot.path, branch: "alveary/task-run")
        ])

        try await fixture.viewModel.deleteThread(task)

        let removeCalls = await fixture.worktreeManager.removeCalls()
        XCTAssertEqual(removeCalls, [
            .init(
                projectPath: sourceRoot.path,
                worktreePath: worktreeRoot.path,
                branch: "alveary/task-run"
            )
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeRoot.path))
        XCTAssertThrowsError(try fixture.taskWorkspaceOwnershipService.validateOwnedWorkspace(workspace))
    }

    func testDeleteTaskRemovesOwnedWorktreeWhenSourceProjectIsMissing() async throws {
        let fixture = try SidebarTestFixture()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-task-missing-source-delete-\(UUID().uuidString)", isDirectory: true)
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
        let task = AgentThread(
            name: "Orphaned worktree task",
            branch: "alveary/task-run",
            mode: .task,
            taskWorkspaceDescriptor: workspace
        )
        task.conversations = [Conversation(id: "orphaned-worktree-task", provider: "codex", thread: task)]
        fixture.context.insert(task)
        try fixture.context.save()

        try await fixture.viewModel.deleteThread(task)

        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeRoot.path))
        XCTAssertThrowsError(try fixture.taskWorkspaceOwnershipService.validateOwnedWorkspace(workspace))
    }

    func testDeleteTaskRemovesUnregisteredOwnedWorktreeWithoutTouchingBranch() async throws {
        let fixture = try SidebarTestFixture()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-task-unregistered-delete-\(UUID().uuidString)", isDirectory: true)
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
            name: "Unregistered worktree task",
            branch: "alveary/task-run",
            mode: .task,
            taskWorkspaceDescriptor: workspace
        )
        task.conversations = [Conversation(id: "unregistered-worktree-task", provider: "codex", thread: task)]
        fixture.context.insert(task)
        try fixture.context.save()

        try await fixture.viewModel.deleteThread(task)

        let branchCalls = await fixture.worktreeManager.deleteBranchCalls()
        XCTAssertTrue(branchCalls.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeRoot.path))
        XCTAssertThrowsError(try fixture.taskWorkspaceOwnershipService.validateOwnedWorkspace(workspace))
    }

    func testDeleteProjectPreservesProjectlessTaskBackedByItsPath() async throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Source", path: "/tmp/task-source-project")
        let task = AgentThread(
            name: "Backed task",
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: project.path,
                ownershipStrategy: .projectLocal,
                sourceProjectPath: project.path
            )
        )
        task.conversations = [Conversation(id: "backed-task", provider: "codex", thread: task)]
        fixture.context.insert(task)
        try fixture.context.save()
        let taskID = task.persistentModelID

        try await fixture.viewModel.deleteProject(project)

        let survivingTask = try XCTUnwrap(fixture.context.resolveThread(id: taskID))
        XCTAssertEqual(survivingTask.mode, .task)
        XCTAssertEqual(survivingTask.taskWorkspaceDescriptor?.sourceProjectPath, "/tmp/task-source-project")
    }

    func testDeleteProjectDetachesAndPreservesAttachedTaskModeThread() async throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Source", path: "/tmp/attached-task-source-project")
        let task = AgentThread(
            name: "Attached task",
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: project.path,
                ownershipStrategy: .projectLocal,
                sourceProjectPath: project.path
            ),
            project: project
        )
        task.conversations = [Conversation(id: "attached-task", provider: "codex", thread: task)]
        project.threads.append(task)
        fixture.context.insert(task)
        try fixture.context.save()
        let taskID = task.persistentModelID
        let sourceProjectPath = project.path

        try await fixture.viewModel.deleteProject(project)

        let survivingTask = try XCTUnwrap(fixture.context.resolveThread(id: taskID))
        XCTAssertEqual(survivingTask.mode, .task)
        XCTAssertNil(survivingTask.project)
        XCTAssertEqual(survivingTask.taskWorkspaceDescriptor?.sourceProjectPath, sourceProjectPath)
    }

    func testDeleteProjectPreservesProjectlessOwnedTaskWorktree() async throws {
        let fixture = try SidebarTestFixture()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-project-delete-task-worktree-\(UUID().uuidString)", isDirectory: true)
        let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
        let worktreeRoot = root.appendingPathComponent("Worktree", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        let project = try fixture.insertProject(name: "Source", path: sourceRoot.path)
        let workspace = try fixture.taskWorkspaceOwnershipService.registerOwnedWorktree(
            at: worktreeRoot.path,
            sourceProjectPath: sourceRoot.path,
            grantedRoots: []
        )
        let task = AgentThread(
            name: "Worktree task",
            mode: .task,
            taskWorkspaceDescriptor: workspace
        )
        task.conversations = [Conversation(id: "worktree-task", provider: "codex", thread: task)]
        fixture.context.insert(task)
        try fixture.context.save()
        let taskID = task.persistentModelID

        try await fixture.viewModel.deleteProject(project)

        XCTAssertNotNil(fixture.context.resolveThread(id: taskID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: worktreeRoot.path))
        XCTAssertNoThrow(try fixture.taskWorkspaceOwnershipService.validateOwnedWorkspace(workspace))
        try? FileManager.default.removeItem(at: root)
    }

    func testDeleteProjectRemovesAttachmentDirectoriesAcrossAllThreads() async throws {
        let invalidations = SidebarControllerInvalidationRecorder()
        let fixture = try SidebarTestFixture(
            invalidateConversationController: invalidations.record
        )
        let project = Project(path: "/tmp/alveary-project-attachment-cleanup", name: "Alveary")
        let first = AgentThread(name: "First", project: project)
        first.conversations = [
            Conversation(id: "first", provider: "claude", isMain: true, displayOrder: 0, thread: first)
        ]
        let second = AgentThread(name: "Second", project: project)
        second.conversations = [
            Conversation(id: "second", provider: "claude", isMain: true, displayOrder: 0, thread: second)
        ]
        project.threads = [first, second]
        fixture.context.insert(project)
        try fixture.context.save()

        try await fixture.viewModel.deleteProject(project)

        let removedConversationIDs = await fixture.attachmentStore.removedConversationIDs
        XCTAssertEqual(removedConversationIDs.sorted(), ["first", "second"])
        XCTAssertEqual(invalidations.conversationIDs.sorted(), ["first", "second"])
    }

    func testTrustEquivalentDraftDeleteCannotReuseOldDraftOrDestroyReplacementRuntime() async throws {
        let providerSessionActions = RecordingProviderSessionActionService(pausesResolution: true)
        let fixture = try SidebarTestFixture(providerSessionActions: providerSessionActions)
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/draft-delete-race")
        let oldDraft = try await fixture.viewModel.openDraftThread(project: project)
        let oldThreadID = oldDraft.persistentModelID
        let oldConversationID = try XCTUnwrap(oldDraft.conversations.first?.id)

        let deletion = Task { @MainActor in
            try await fixture.viewModel.deleteThread(oldDraft)
        }
        await providerSessionActions.waitUntilResolutionBegins()
        defer { Task { await providerSessionActions.resumeResolution() } }

        XCTAssertNil(fixture.context.resolveThread(id: oldThreadID))
        let replacement = try await fixture.viewModel.openDraftThread(project: project)
        let replacementID = replacement.persistentModelID
        let replacementConversationID = try XCTUnwrap(replacement.conversations.first?.id)
        replacement.isDraft = false
        try fixture.context.save()

        await providerSessionActions.resumeResolution()
        try await deletion.value

        XCTAssertNotEqual(replacementID, oldThreadID)
        XCTAssertNotNil(fixture.context.resolveThread(id: replacementID))
        let destroyCalls = await fixture.agentsManager.destroyCalls()
        XCTAssertEqual(destroyCalls, [oldConversationID])
        XCTAssertNotEqual(replacementConversationID, oldConversationID)
    }

    func testProjectDeleteRejectsStaleProjectWhileCleanupIsInFlightAndPreservesOtherDraft() async throws {
        let providerSessionActions = RecordingProviderSessionActionService(pausesResolution: true)
        let fixture = try SidebarTestFixture(providerSessionActions: providerSessionActions)
        let deletedProject = try fixture.insertProject(name: "Deleted", path: "/tmp/draft-project-delete-race")
        let deletedProjectID = deletedProject.persistentModelID
        let oldDraft = try await fixture.viewModel.openDraftThread(project: deletedProject)
        let oldConversationID = try XCTUnwrap(oldDraft.conversations.first?.id)

        let deletion = Task { @MainActor in
            try await fixture.viewModel.deleteProject(deletedProject)
        }
        await providerSessionActions.waitUntilResolutionBegins()
        defer { Task { await providerSessionActions.resumeResolution() } }

        XCTAssertNil(fixture.context.resolveProject(id: deletedProjectID))
        do {
            _ = try await fixture.viewModel.openDraftThread(project: deletedProject)
            XCTFail("Expected the deleting project to remain unavailable")
        } catch SidebarViewModelError.projectMissing {
            // expected
        }

        let survivingProject = try fixture.insertProject(name: "Surviving", path: "/tmp/draft-project-surviving")
        let survivingDraft = try await fixture.viewModel.openDraftThread(project: survivingProject)
        let survivingID = survivingDraft.persistentModelID
        survivingDraft.isDraft = false
        try fixture.context.save()

        await providerSessionActions.resumeResolution()
        try await deletion.value

        XCTAssertNotNil(fixture.context.resolveThread(id: survivingID))
        let destroyCalls = await fixture.agentsManager.destroyCalls()
        XCTAssertEqual(destroyCalls, [oldConversationID])
    }

    func testDeleteThreadDeletesModelBeforeReportingRuntimeCleanupFailure() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"]
        )
        await fixture.agentsManager.setDestroyError(.destroyFailed("main"), for: "main")

        do {
            try await fixture.viewModel.deleteThread(thread)
            XCTFail("Expected delete to throw")
        } catch let error as SidebarViewModelError {
            guard case .threadDeleteCleanupFailed(let underlying) = error,
                  let mockError = underlying as? SidebarMockAgentsManager.MockError else {
                XCTFail("Expected thread delete cleanup failure")
                return
            }
            XCTAssertEqual(mockError, .destroyFailed("main"))
        }

        XCTAssertFalse(try fixture.threadExists(thread))
        let removedConversationIDs = await fixture.attachmentStore.removedConversationIDs
        XCTAssertEqual(removedConversationIDs, ["main"])
    }

    func testDeleteThreadKeepsModelDeletedWhenWorktreeCleanupFails() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            branch: "alveary/live",
            worktreePath: "/tmp/alveary-worktree",
            hasCompletedInitialSetup: true,
            useWorktree: true
        )
        await fixture.worktreeManager.setRemoveError(.removeFailed)

        do {
            try await fixture.viewModel.deleteThread(thread)
            XCTFail("Expected delete to throw")
        } catch let error as SidebarViewModelError {
            guard case .threadDeleteCleanupFailed(let underlying) = error,
                  let mockError = underlying as? SidebarMockWorktreeManager.MockError else {
                XCTFail("Expected thread delete cleanup failure")
                return
            }
            XCTAssertEqual(mockError, .removeFailed)
        }

        XCTAssertFalse(try fixture.threadExists(thread))
    }

    func testDeleteProjectDoesNotSweepUnownedWorktrees() async throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let thread = AgentThread(name: "Primary", project: project)
        thread.conversations = [
            Conversation(id: "main", title: "Main", provider: "claude", isMain: true, displayOrder: 0, thread: thread)
        ]

        project.threads = [thread]
        fixture.context.insert(project)
        try fixture.context.save()
        await fixture.worktreeManager.setRemoveAllError(.removeAllFailed)

        try await fixture.viewModel.deleteProject(project)

        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<Project>()), 0)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<AgentThread>()), 0)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<Conversation>()), 0)
        let removeAllCalls = await fixture.worktreeManager.removeAllCalls()
        XCTAssertTrue(removeAllCalls.isEmpty)
        let removedConversationIDs = await fixture.attachmentStore.removedConversationIDs
        XCTAssertEqual(removedConversationIDs, ["main"])
    }
}

private enum SidebarDeletionCommitTestError: Error {
    case saveFailed
}

@MainActor
private final class SidebarControllerInvalidationRecorder {
    private(set) var conversationIDs: [String] = []

    func record(_ conversationID: String) {
        conversationIDs.append(conversationID)
    }
}

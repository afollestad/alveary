import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testOpenTaskDraftCreatesProjectlessOwnedWorkspace() async throws {
        let fixture = try SidebarTestFixture()

        let draft = try await fixture.viewModel.openTaskDraft()
        let reused = try await fixture.viewModel.openTaskDraft()

        let savedDraft = try fixture.requireThread(draft)
        XCTAssertEqual(savedDraft.mode, .task)
        XCTAssertTrue(savedDraft.isDraft)
        XCTAssertNil(savedDraft.project)
        XCTAssertEqual(savedDraft.conversations.count, 1)
        XCTAssertTrue(savedDraft.conversations.first?.isMain == true)
        XCTAssertEqual(savedDraft.taskWorkspaceDescriptor?.ownershipStrategy, .privateOwned)
        XCTAssertEqual(savedDraft.primaryWorkingDirectory, savedDraft.taskWorkspaceDescriptor?.primaryRoot)
        XCTAssertEqual(reused.persistentModelID, savedDraft.persistentModelID)
    }

    func testReopeningTaskDraftPreservesEditedFolderAccessAndPrivateWorkspace() async throws {
        let fixture = try SidebarTestFixture()
        let draft = try await fixture.viewModel.openTaskDraft()
        let customGrant = SourceFolderSnapshot(path: "/tmp/reopened-task-grant")
        try draft.replaceAdditionalFolders([customGrant])
        draft.draftHasExplicitGrants = true
        try fixture.context.save()
        let savedWorkspace = draft.taskWorkspaceDescriptor

        let reopened = try await fixture.viewModel.openTaskDraft()

        XCTAssertEqual(reopened.persistentModelID, draft.persistentModelID)
        XCTAssertEqual(reopened.taskWorkspaceDescriptor, savedWorkspace)
        XCTAssertEqual(reopened.workspaceSnapshot?.grants, [customGrant])
        XCTAssertTrue(reopened.draftHasExplicitGrants)
    }

    func testProjectAndTaskDraftsShareIdentityAndLatestDestination() async throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Alpha", path: "/tmp/draft-mode-alpha")
        let projectOpen = Task { @MainActor in
            try await fixture.viewModel.openDraftThread(project: project).persistentModelID
        }
        let taskOpen = Task { @MainActor in
            try await fixture.viewModel.openTaskDraft().persistentModelID
        }
        let projectDraftID = try await projectOpen.value
        let taskDraftID = try await taskOpen.value
        XCTAssertEqual(projectDraftID, taskDraftID)
        let draft = try XCTUnwrap(fixture.context.resolveThread(id: taskDraftID))
        XCTAssertEqual(draft.mode, .task)
        XCTAssertNil(draft.project)
        let conversationID = try XCTUnwrap(draft.conversations.first?.id)
        let privateRoot = try XCTUnwrap(draft.primaryWorkingDirectory)

        let moved = try await fixture.viewModel.openDraftThread(project: project)
        XCTAssertEqual(moved.persistentModelID, taskDraftID)
        XCTAssertEqual(moved.conversations.first?.id, conversationID)
        XCTAssertEqual(moved.primaryWorkingDirectory, project.path)
        XCTAssertEqual(moved.workspaceSnapshot?.rootsExplicitlyManaged, true)
        for _ in 0..<100 where FileManager.default.fileExists(atPath: privateRoot) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: privateRoot))

        moved.isDraft = false
        try fixture.context.save()
        fixture.viewModel.noteDraftMaterialized(mode: moved.mode)
        let replacement = try await fixture.viewModel.openTaskDraft()
        XCTAssertNotEqual(replacement.persistentModelID, taskDraftID)
    }

    func testEmptyProjectAndTasksReusePrivateDraftWorkspace() async throws {
        let fixture = try SidebarTestFixture()
        let empty = Project(name: "Empty")
        fixture.context.insert(empty)
        try fixture.context.save()
        let draft = try await fixture.viewModel.openDraftThread(project: empty)
        let threadID = draft.persistentModelID
        let root = try XCTUnwrap(draft.primaryWorkingDirectory)
        let conversationID = draft.conversations.first?.id
        XCTAssertEqual(draft.project?.id, empty.id)
        XCTAssertEqual(draft.mode, .task)
        XCTAssertFalse(draft.useWorktree)
        XCTAssertEqual(draft.workspaceSnapshot?.sourceFolders, [])

        let moved = try await fixture.viewModel.openTaskDraft()
        XCTAssertEqual(moved.persistentModelID, threadID)
        XCTAssertEqual(moved.conversations.first?.id, conversationID)
        XCTAssertEqual(moved.primaryWorkingDirectory, root)
        XCTAssertNil(moved.project)
        let returned = try await fixture.viewModel.openDraftThread(project: empty)
        XCTAssertEqual(returned.primaryWorkingDirectory, root)
        XCTAssertEqual(returned.project?.id, empty.id)
    }

    func testFailedMoveFromPrivateDraftPreservesWorkspaceAndConversation() async throws {
        let fixture = try SidebarTestFixture(saveDraftProjectMove: { _ in throw TaskDraftCreationSaveError.forced })
        let project = try fixture.insertProject(name: "Source", path: "/tmp/draft-rollback-source")
        let draft = try await fixture.viewModel.openTaskDraft()
        let root = try XCTUnwrap(draft.primaryWorkingDirectory)
        let conversationID = draft.conversations.first?.id
        do {
            _ = try await fixture.viewModel.openDraftThread(project: project)
            XCTFail("Expected the destination save to fail")
        } catch TaskDraftCreationSaveError.forced { }
        XCTAssertEqual(draft.primaryWorkingDirectory, root)
        XCTAssertEqual(draft.conversations.first?.id, conversationID)
        XCTAssertEqual(draft.mode, .task)
        XCTAssertNil(draft.project)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root))
    }

    func testTaskDraftSaveFailureRemovesNewOwnedWorkspace() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-task-draft-save-failure-\(UUID().uuidString)", isDirectory: true)
        let privateRoot = root.appendingPathComponent("Private", isDirectory: true)
        let service = DefaultTaskWorkspaceOwnershipService(
            privateWorkspacesRoot: privateRoot,
            worktreeOwnershipRecordsRoot: root.appendingPathComponent("Worktrees", isDirectory: true)
        )
        let fixture = try SidebarTestFixture(
            taskWorkspaceOwnershipService: service,
            saveThreadCreation: { _ in throw TaskDraftCreationSaveError.forced }
        )

        do {
            _ = try await fixture.viewModel.openTaskDraft()
            XCTFail("Expected Task draft creation to fail")
        } catch TaskDraftCreationSaveError.forced {
            // expected
        }

        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<AgentThread>()), 0)
        let remainingChildren = (try? FileManager.default.contentsOfDirectory(atPath: privateRoot.path)) ?? []
        XCTAssertTrue(remainingChildren.isEmpty)
        try? FileManager.default.removeItem(at: root)
    }

    func testAttachedTaskModeThreadRendersAsAChildOfItsProject() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Source", path: "/tmp/attached-task-sidebar-source")
        let task = AgentThread(
            name: "Attached task",
            isPinned: true,
            pinnedSortOrder: 0,
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: project.path,
                ownershipStrategy: .projectLocal,
                sourceProjectPath: project.path
            ),
            project: project
        )
        project.threads.append(task)
        fixture.context.insert(task)
        try fixture.context.save()

        // A Task with a project is one of its children; only a projectless Task lives in `Tasks`.
        XCTAssertTrue(try fixture.renderSnapshot().hasAnyActiveThreads(for: project))
        // Its project is unpinned, so the pin still promotes it to a standalone Pinned row.
        XCTAssertEqual(fixture.viewModel.pinnedThreads().map(\.persistentModelID), [task.persistentModelID])
        XCTAssertEqual(fixture.viewModel.pinnedItems(projects: []).map(\.dragItem), [.pinnedTask(task.persistentModelID)])
    }
}

private enum TaskDraftCreationSaveError: Error {
    case forced
}

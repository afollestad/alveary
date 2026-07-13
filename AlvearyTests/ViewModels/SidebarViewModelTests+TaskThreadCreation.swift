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

    func testProjectAndTaskDraftsKeepIndependentIdentities() async throws {
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
        let createdProjectDraft = try XCTUnwrap(fixture.context.resolveThread(id: projectDraftID))
        let createdTaskDraft = try XCTUnwrap(fixture.context.resolveThread(id: taskDraftID))

        XCTAssertNotEqual(createdProjectDraft.persistentModelID, createdTaskDraft.persistentModelID)
        XCTAssertEqual(createdProjectDraft.mode, .project)
        XCTAssertEqual(createdTaskDraft.mode, .task)
        XCTAssertEqual(createdProjectDraft.project?.path, project.path)
        XCTAssertNil(createdTaskDraft.project)

        createdTaskDraft.isDraft = false
        try fixture.context.save()
        fixture.viewModel.noteDraftMaterialized(mode: .task)

        let reusedProjectDraft = try await fixture.viewModel.openDraftThread(project: project)
        let replacementTaskDraft = try await fixture.viewModel.openTaskDraft()
        XCTAssertEqual(reusedProjectDraft.persistentModelID, createdProjectDraft.persistentModelID)
        XCTAssertNotEqual(replacementTaskDraft.persistentModelID, createdTaskDraft.persistentModelID)
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

    func testAttachedTaskModeThreadDoesNotAppearInProjectOrPinnedSections() throws {
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

        XCTAssertTrue(fixture.viewModel.activeThreads(for: project).isEmpty)
        XCTAssertFalse(fixture.viewModel.hasAnyActiveThreads(for: project))
        XCTAssertTrue(fixture.viewModel.pinnedThreads().isEmpty)
        XCTAssertTrue(fixture.viewModel.pinnedItems(projects: []).isEmpty)
    }
}

private enum TaskDraftCreationSaveError: Error {
    case forced
}

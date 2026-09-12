import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testUnplacedSourceWorkspaceCanPinAndMoveBackToTasksWithoutChangingRoots() throws {
        let fixture = try SidebarTestFixture()
        let source = SourceFolderSnapshot(path: "/tmp/independent-source", gitBranch: "main")
        let thread = AgentThread(name: "Independent source", mode: .project)
        thread.workspaceSnapshot = WorkspaceSnapshot(primarySource: source, grants: [SourceFolderSnapshot(path: "/tmp/grant")])
        thread.conversations = [Conversation(thread: thread)]
        fixture.context.insert(thread)
        try fixture.context.save()
        let workspace = thread.workspaceSnapshot

        try fixture.viewModel.setThreadPinned(thread, isPinned: true)
        XCTAssertTrue(SidebarOrderNormalization.isVisiblePinnedSidebarThread(thread))
        XCTAssertEqual(SidebarPinnedItem(thread: thread).dragItem, .pinnedTask(thread.persistentModelID))
        XCTAssertTrue(try fixture.viewModel.commitSidebarDrop(
            dragItem: .pinnedTask(thread.persistentModelID),
            target: SidebarDropTarget(section: .tasks, placement: .end)
        ))
        XCTAssertFalse(thread.isPinned)
        XCTAssertEqual(thread.workspaceSnapshot, workspace)
        XCTAssertEqual(thread.effectiveMode, .project)
    }

    func testProjectEditorCreatesEmptyAndSharedFolderProjects() throws {
        let fixture = try SidebarTestFixture()
        let empty = try fixture.viewModel.saveProjectConfiguration(ProjectConfiguration(name: " Empty "))
        XCTAssertEqual(empty.name, "Empty")
        XCTAssertTrue(empty.folders.isEmpty)
        XCTAssertNil(empty.primaryFolderID)
        let source = SourceFolderSnapshot(path: "/tmp/shared-source", gitBranch: "main")
        let first = try fixture.viewModel.saveProjectConfiguration(ProjectConfiguration(name: "First", folders: [source]))
        let second = try fixture.viewModel.saveProjectConfiguration(ProjectConfiguration(name: "Second", folders: [source]))
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.primaryFolderID, second.primaryFolderID)
        XCTAssertEqual(first.primaryFolder?.path, second.primaryFolder?.path)
        XCTAssertNil(fixture.context.resolveProject(path: source.path))
        XCTAssertEqual(fixture.context.resolveProject(projectID: second.id)?.name, "Second")
    }

    func testProjectEditorPrimaryRemovalAndCancelKeepPersistedMembershipUntouched() throws {
        let fixture = try SidebarTestFixture()
        let folders = [SourceFolderSnapshot(path: "/tmp/first"), SourceFolderSnapshot(path: "/tmp/second")]
        let project = try fixture.viewModel.saveProjectConfiguration(ProjectConfiguration(name: "Project", folders: folders))
        let original = ProjectConfiguration(project: project)
        var draft = original
        draft.name = "Not saved"
        draft.remove(path: folders[0].path)
        XCTAssertEqual(draft.primaryFolderPath, folders[1].path)
        XCTAssertEqual(ProjectConfiguration(project: project), original)
        draft.remove(path: folders[1].path)
        XCTAssertNil(draft.primaryFolderPath)
        XCTAssertEqual(ProjectConfiguration(project: project), original)
    }

    func testSavingProjectEditPreservesIdentityAndExistingThreadWorkspace() async throws {
        let fixture = try SidebarTestFixture()
        let folders = [SourceFolderSnapshot(path: "/tmp/first"), SourceFolderSnapshot(path: "/tmp/second")]
        let project = try fixture.viewModel.saveProjectConfiguration(ProjectConfiguration(name: "Project", folders: folders))
        let projectID = project.id
        let secondMembershipID = project.orderedFolders[1].id
        let thread = try await fixture.viewModel.createThread(project: project, provider: "codex", permissionMode: "never")
        let workspace = thread.workspaceSnapshot
        var draft = ProjectConfiguration(project: project)
        draft.name = "Renamed"
        draft.remove(path: folders[0].path)

        let saved = try fixture.viewModel.saveProjectConfiguration(draft, projectID: projectID)

        XCTAssertEqual(saved.id, projectID)
        XCTAssertEqual(saved.name, "Renamed")
        XCTAssertEqual(saved.primaryFolderID, secondMembershipID)
        XCTAssertEqual(thread.workspaceSnapshot, workspace)
        XCTAssertEqual(thread.primaryWorkingDirectory, folders[0].path)
        XCTAssertEqual(saved.workspaceSnapshot().primarySource?.path, folders[1].path)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ProjectFolder>()), 1)
    }

    func testProjectEditorSaveFailureRestoresRemovedMembershipsAndUnrelatedChanges() throws {
        let fixture = try SidebarTestFixture()
        let folders = [
            SourceFolderSnapshot(path: "/tmp/original", gitRemote: "https://github.com/owner/original.git", remoteName: "origin"),
            SourceFolderSnapshot(path: "/tmp/retained", gitBranch: "main", baseRef: "develop")
        ]
        let project = try fixture.viewModel.saveProjectConfiguration(ProjectConfiguration(name: "Original", folders: folders))
        let other = try fixture.viewModel.saveProjectConfiguration(ProjectConfiguration(name: "Other"))
        let projectID = project.id
        let original = ProjectConfiguration(project: project)
        let membershipIDs = project.orderedFolders.map(\.id)
        other.name = "Unrelated pending edit"
        var draft = original
        draft.remove(path: folders[0].path)
        try draft.add(SourceFolderSnapshot(path: "/tmp/new-folder"))
        draft.folders[0].baseRef = "changed-before-failure"
        draft.name = "Failed edit"

        XCTAssertThrowsError(try fixture.viewModel.saveProjectConfiguration(draft, projectID: projectID, save: { context in
            context.processPendingChanges()
            throw ProjectEditingTestError.saveFailed
        }))

        let restored = try XCTUnwrap(fixture.context.resolveProject(projectID: projectID))
        XCTAssertEqual(ProjectConfiguration(project: project), original)
        XCTAssertEqual(ProjectConfiguration(project: restored), original)
        XCTAssertEqual(restored.orderedFolders.map(\.id), membershipIDs)
        XCTAssertEqual(restored.orderedFolders.map(\.sortOrder), [0, 1])
        XCTAssertTrue(restored.folders.allSatisfy { $0.project?.id == projectID })
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ProjectFolder>()), 2)
        try fixture.context.save()
        let verification = ModelContext(fixture.container)
        let persisted = try XCTUnwrap(verification.resolveProject(projectID: projectID))
        XCTAssertEqual(ProjectConfiguration(project: persisted), original)
        XCTAssertEqual(persisted.orderedFolders.map(\.id), membershipIDs)
        XCTAssertEqual(verification.resolveProject(projectID: other.id)?.name, "Unrelated pending edit")
    }

    func testProjectEditorRejectsMissingNameAndDuplicateMemberships() throws {
        let fixture = try SidebarTestFixture()
        XCTAssertThrowsError(try fixture.viewModel.saveProjectConfiguration(ProjectConfiguration(name: "  ")))
        let source = SourceFolderSnapshot(path: "/tmp/source")
        XCTAssertThrowsError(try fixture.viewModel.saveProjectConfiguration(ProjectConfiguration(name: "Duplicate", folders: [source, source])))
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<Project>()), 0)
    }
}

private enum ProjectEditingTestError: Error {
    case saveFailed
}

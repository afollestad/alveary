import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testProjectEditRefreshesOpenDraftDefaultsAcrossWindows() async throws {
        let fixture = try SidebarTestFixture(createWorktreeByDefault: true)
        let first = SourceFolderSnapshot(path: "/tmp/draft-default-first", gitBranch: "main")
        let second = SourceFolderSnapshot(path: "/tmp/draft-default-second", gitBranch: "main")
        let project = try fixture.viewModel.saveProjectConfiguration(ProjectConfiguration(name: "Project", folders: [first, second]))
        let draft = try await fixture.viewModel.openDraftThread(project: project)
        let conversationID = draft.conversations.first?.id
        let otherWindow = SidebarViewModel(
            agentsManager: fixture.agentsManager, modelContext: fixture.context, shell: fixture.shell,
            gitHubCLI: fixture.gitHubCLI, worktreeManager: fixture.worktreeManager, settingsService: fixture.settingsService,
            taskWorkspaceOwnershipService: fixture.taskWorkspaceOwnershipService, notificationManager: fixture.notificationManager
        )
        let added = SourceFolderSnapshot(path: "/tmp/draft-default-added")

        _ = try otherWindow.saveProjectConfiguration(
            ProjectConfiguration(name: "Renamed", folders: [second, added]), projectID: project.id
        )

        XCTAssertEqual(draft.primaryWorkingDirectory, second.path)
        XCTAssertEqual(draft.workspaceSnapshot?.grants, [added])
        XCTAssertTrue(draft.useWorktree)
        XCTAssertTrue(draft.isDraft)
        XCTAssertEqual(draft.conversations.first?.id, conversationID)
        let verification = ModelContext(fixture.container)
        XCTAssertEqual(verification.resolveThread(id: draft.persistentModelID)?.workspaceSnapshot, draft.workspaceSnapshot)
    }

    func testProjectEditReleasesReplacedPrivateDraftWorkspaceAfterSave() async throws {
        let fixture = try SidebarTestFixture()
        let source = SourceFolderSnapshot(path: "/tmp/draft-empty-source")
        let project = try fixture.viewModel.saveProjectConfiguration(ProjectConfiguration(name: "Project", folders: [source]))
        let draft = try await fixture.viewModel.openDraftThread(project: project)
        let conversationID = draft.conversations.first?.id
        _ = try fixture.viewModel.saveProjectConfiguration(ProjectConfiguration(name: "Empty"), projectID: project.id)
        let privateWorkspace = try XCTUnwrap(draft.taskWorkspaceDescriptor)
        XCTAssertEqual(draft.mode, .task)
        XCTAssertTrue(FileManager.default.fileExists(atPath: privateWorkspace.primaryRoot))

        _ = try fixture.viewModel.saveProjectConfiguration(
            ProjectConfiguration(name: "Source", folders: [source]), projectID: project.id, save: { context in
                XCTAssertTrue(FileManager.default.fileExists(atPath: privateWorkspace.primaryRoot))
                try context.save()
            }
        )

        XCTAssertEqual(draft.mode, .project)
        XCTAssertEqual(draft.primaryWorkingDirectory, source.path)
        XCTAssertEqual(draft.conversations.first?.id, conversationID)
        for _ in 0..<100 where FileManager.default.fileExists(atPath: privateWorkspace.primaryRoot) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: privateWorkspace.primaryRoot))
    }

    func testFailedProjectEditRestoresDraftAndCleansOnlyNewPrivateWorkspace() async throws {
        let fixture = try SidebarTestFixture()
        let source = SourceFolderSnapshot(path: "/tmp/draft-failed-source")
        let project = try fixture.viewModel.saveProjectConfiguration(ProjectConfiguration(name: "Project", folders: [source]))
        let draft = try await fixture.viewModel.openDraftThread(project: project)
        let original = draft.workspaceSnapshot
        let originalFolderID = project.primaryFolderID
        var failedWorkspace: TaskWorkspaceDescriptor?

        XCTAssertThrowsError(try fixture.viewModel.saveProjectConfiguration(
            ProjectConfiguration(name: "Empty"), projectID: project.id, save: { context in
                failedWorkspace = draft.taskWorkspaceDescriptor
                context.processPendingChanges()
                throw DraftProjectEditTestError.saveFailed
            }
        ))

        XCTAssertEqual(draft.workspaceSnapshot, original)
        XCTAssertEqual(draft.mode, .project)
        XCTAssertEqual(project.primaryFolder?.path, source.path)
        XCTAssertEqual(project.primaryFolderID, originalFolderID)
        let failedRoot = try XCTUnwrap(failedWorkspace?.primaryRoot)
        for _ in 0..<100 where FileManager.default.fileExists(atPath: failedRoot) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: failedRoot))

        _ = try fixture.viewModel.saveProjectConfiguration(ProjectConfiguration(name: "Empty"), projectID: project.id)
        let retainedWorkspace = try XCTUnwrap(draft.taskWorkspaceDescriptor)
        defer { try? fixture.taskWorkspaceOwnershipService.removeOwnedWorkspace(retainedWorkspace) }
        XCTAssertThrowsError(try fixture.viewModel.saveProjectConfiguration(
            ProjectConfiguration(name: "Source", folders: [source]), projectID: project.id,
            save: { context in
                context.processPendingChanges()
                throw DraftProjectEditTestError.saveFailed
            }
        ))
        XCTAssertEqual(draft.taskWorkspaceDescriptor, retainedWorkspace)
        XCTAssertEqual(draft.mode, .task)
        XCTAssertTrue(project.folders.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: retainedWorkspace.primaryRoot))
        XCTAssertNil(project.primaryFolder)
        XCTAssertEqual(project.name, "Empty")
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ProjectFolder>()), 0)
        try fixture.context.save()
        let verification = ModelContext(fixture.container)
        let persisted = try XCTUnwrap(verification.resolveProject(projectID: project.id))
        XCTAssertTrue(persisted.folders.isEmpty)
        XCTAssertEqual(verification.resolveThread(id: draft.persistentModelID)?.taskWorkspaceDescriptor, retainedWorkspace)

        try await assertProjectDraftRetryReleasesWorkspace(
            fixture, project: project, draft: draft, source: source, workspace: retainedWorkspace
        )
    }
}

private enum DraftProjectEditTestError: Error {
    case saveFailed
}

@MainActor
private func assertProjectDraftRetryReleasesWorkspace(
    _ fixture: SidebarTestFixture, project: Project, draft: AgentThread, source: SourceFolderSnapshot, workspace: TaskWorkspaceDescriptor
) async throws {
    _ = try fixture.viewModel.saveProjectConfiguration(
        ProjectConfiguration(name: "Source", folders: [source]), projectID: project.id
    )
    XCTAssertEqual(project.orderedFolders.map(\.path), [source.path])
    XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ProjectFolder>()), 1)
    XCTAssertEqual(draft.mode, .project)
    for _ in 0..<100 where FileManager.default.fileExists(atPath: workspace.primaryRoot) {
        try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.primaryRoot))
}

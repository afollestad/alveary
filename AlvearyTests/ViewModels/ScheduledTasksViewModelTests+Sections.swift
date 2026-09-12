import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTasksViewModelTests {
    func testProjectOptionsRefreshAfterFolderEditsWithoutChangingSelectedDraft() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let project = Project(path: "/tmp/scheduled-original", name: "Original")
        fixture.context.insert(project)
        try fixture.context.save()
        fixture.viewModel.reload()
        fixture.viewModel.requestCreate()
        var draft = try XCTUnwrap(fixture.viewModel.pendingEditorDraft)
        draft.projectID = project.id
        draft.workspaceSnapshot = project.workspaceSnapshot()
        draft.projectPath = project.path
        draft.title = "Keep my unsaved title"
        fixture.viewModel.updateActiveDraft(draft)

        let added = ProjectFolder(snapshot: SourceFolderSnapshot(path: "/tmp/scheduled-new", gitBranch: "main"), sortOrder: 1)
        added.project = project
        project.folders.append(added)
        fixture.context.insert(added)
        project.primaryFolderID = added.id
        project.name = "Renamed"
        try fixture.context.save()
        fixture.notificationCenter.post(name: .workspaceConfigurationChanged, object: nil)

        let deadline = Date().addingTimeInterval(2)
        while fixture.viewModel.projects.first?.name != "Renamed", Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(fixture.viewModel.projects.first?.workspaceSnapshot, project.workspaceSnapshot())
        XCTAssertEqual(fixture.viewModel.pendingEditorDraft, draft)
    }

    func testNewGrantMetadataSurvivesPrimarySelectionAndScheduleSave() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        var draft = fixture.viewModel.makeNewDraft()
        draft.title = "Secondary repository"
        draft.prompt = "Review this repository."
        let original = SourceFolderSnapshot(path: "/tmp/scheduled-original", gitBranch: "main")
        let added = SourceFolderSnapshot(
            path: "/tmp/scheduled-repo/sub", gitRemote: "git@github.com:owner/secondary.git",
            remoteName: "origin", gitBranch: "main", baseRef: "main", githubRepository: "owner/secondary"
        )
        draft.workspaceKind = .project
        draft.workspaceStrategy = .worktree
        draft.workspaceSnapshot = WorkspaceSnapshot(primarySource: original)
        draft.addFolderGrants([added])
        draft.selectPrimaryFolder(path: added.path)

        XCTAssertEqual(draft.workspaceSnapshot?.primarySource, added)
        XCTAssertEqual(draft.workspaceStrategy, .worktree)
        XCTAssertTrue(fixture.viewModel.save(draft))
        let definition = try XCTUnwrap(try fixture.context.fetch(FetchDescriptor<ScheduledTask>()).first)
        XCTAssertEqual(definition.workspaceSnapshot?.primarySource, added)
        XCTAssertEqual(definition.workspaceSnapshot?.grants, [original])
        XCTAssertEqual(definition.workspaceStrategy, .worktree)
    }

    func testSourceWorkspaceWithoutProjectPlacementRetainsItsCustomSectionOnSave() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let section = SidebarSection(id: "reports", kind: .custom, name: "Reports", sortOrder: 3)
        fixture.context.insert(section)
        try fixture.context.save()
        var draft = fixture.viewModel.makeNewDraft()
        draft.title = "Source workspace"
        draft.prompt = "Do the work."
        draft.workspaceKind = .project
        draft.workspaceStrategy = .localCheckout
        draft.workspaceSnapshot = WorkspaceSnapshot(primarySource: SourceFolderSnapshot(path: "/tmp/source-workspace"))
        draft.projectPath = "/tmp/source-workspace"
        draft.sectionID = section.id

        XCTAssertTrue(fixture.viewModel.save(draft))

        let definition = try XCTUnwrap(try fixture.context.fetch(FetchDescriptor<ScheduledTask>()).first)
        XCTAssertNil(definition.project)
        XCTAssertEqual(definition.threadSection?.id, section.id)
        XCTAssertEqual(definition.workspaceSnapshot?.primarySource?.path, draft.projectPath)
    }

    func testSectionOptionsListCustomSectionsInSidebarOrderExcludingBuiltins() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        fixture.context.insert(SidebarSection(id: "pinned-row", kind: .pinned, name: "Pinned", sortOrder: 0))
        fixture.context.insert(SidebarSection(id: "reports", kind: .custom, name: "Reports", sortOrder: 4))
        fixture.context.insert(SidebarSection(id: "audits", kind: .custom, name: "Audits", sortOrder: 3))
        try fixture.context.save()

        fixture.viewModel.reload()

        XCTAssertEqual(fixture.viewModel.sectionOptions.map(\.id), ["audits", "reports"])
    }

    func testSectionOptionsReloadWhenSectionsChangeNotificationFires() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        fixture.viewModel.reload()
        XCTAssertTrue(fixture.viewModel.sectionOptions.isEmpty)

        // The sidebar sees section changes through its own `@Query`; an open editor only learns
        // about them through the service's notification.
        let sectionService = SidebarSectionService(
            modelContext: fixture.context,
            notificationCenter: fixture.notificationCenter
        )
        _ = try sectionService.createSection(name: "Reports")

        let deadline = Date().addingTimeInterval(2)
        while fixture.viewModel.sectionOptions.isEmpty, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(fixture.viewModel.sectionOptions.map(\.name), ["Reports"])
    }

    func testSaveResolvesTheSectionAndRejectsAVanishedOne() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let section = SidebarSection(id: "reports", kind: .custom, name: "Reports", sortOrder: 3)
        fixture.context.insert(section)
        try fixture.context.save()
        var draft = fixture.viewModel.makeNewDraft()
        draft.title = "Sectioned"
        draft.prompt = "Do the work."
        draft.sectionID = "reports"

        XCTAssertTrue(fixture.viewModel.save(draft))
        let definition = try XCTUnwrap(try fixture.context.fetch(FetchDescriptor<ScheduledTask>()).first)
        XCTAssertEqual(definition.destination, .reusedThread)
        XCTAssertEqual(definition.threadSection?.id, "reports")

        var staleDraft = fixture.viewModel.makeNewDraft()
        staleDraft.title = "Stale"
        staleDraft.prompt = "Do the work."
        staleDraft.sectionID = "vanished"
        XCTAssertFalse(fixture.viewModel.save(staleDraft))
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ScheduledTask>()), 1)
    }

    func testEditDraftRestoresTheSectionAndProjectBackedDraftsDropIt() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let section = SidebarSection(id: "reports", kind: .custom, name: "Reports", sortOrder: 3)
        fixture.context.insert(section)
        try fixture.context.save()
        var draft = fixture.viewModel.makeNewDraft()
        draft.title = "Sectioned"
        draft.prompt = "Do the work."
        draft.sectionID = "reports"
        XCTAssertTrue(fixture.viewModel.save(draft))
        let definition = try XCTUnwrap(try fixture.context.fetch(FetchDescriptor<ScheduledTask>()).first)

        let editDraft = try XCTUnwrap(fixture.viewModel.makeEditDraft(definitionID: definition.id))
        XCTAssertEqual(editDraft.sectionID, "reports")

        // A hidden stale pick must not survive a Project selection at save time.
        let project = Project(path: "/tmp/section-project", name: "Sectioned Project")
        fixture.context.insert(project)
        try fixture.context.save()
        var projectDraft = editDraft
        projectDraft.workspaceKind = .project
        projectDraft.projectPath = project.path
        projectDraft.projectID = project.id
        projectDraft.workspaceSnapshot = project.workspaceSnapshot()
        XCTAssertTrue(fixture.viewModel.save(projectDraft))
        XCTAssertNil(definition.threadSection)
    }
}

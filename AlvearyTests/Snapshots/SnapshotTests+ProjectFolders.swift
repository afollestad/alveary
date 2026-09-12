import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testNewThreadInEmptyProject() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.viewModel.saveProjectConfiguration(ProjectConfiguration(name: "Research"))
        let thread = AgentThread(
            name: "New thread", isDraft: true, mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/TaskWorkspaces/Private/research", grantedRoots: [],
                ownershipStrategy: .privateOwned, ownershipMarkerID: "research"
            ),
            project: project
        )
        assertMacSnapshot(
            EmptyThreadState(
                setupPhase: nil, isCancellingInitialSetup: false, thread: thread, projects: [project],
                workspaceConfiguration: emptyThreadWorkspaceConfiguration(for: thread)
            ),
            size: CGSize(width: 420, height: 560), named: "new_thread_empty_project"
        )
    }

    func testNewThreadWithMultipleSourceFolders() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.viewModel.saveProjectConfiguration(projectFolderConfiguration)
        let thread = AgentThread(name: "New thread", isDraft: true, project: project)
        assertMacSnapshot(
            EmptyThreadState(
                setupPhase: nil, isCancellingInitialSetup: false, thread: thread, projects: [project],
                workspaceConfiguration: emptyThreadWorkspaceConfiguration(for: thread)
            ),
            size: CGSize(width: 420, height: 560), named: "new_thread_multiple_sources"
        )
    }

    func testNewThreadWithMultipleSourceFoldersWorktree() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.viewModel.saveProjectConfiguration(projectFolderConfiguration)
        let thread = AgentThread(name: "New thread", useWorktree: true, isDraft: true, project: project)
        assertMacSnapshot(
            EmptyThreadState(
                setupPhase: nil, isCancellingInitialSetup: false, thread: thread, projects: [project],
                workspaceConfiguration: emptyThreadWorkspaceConfiguration(for: thread)
            ),
            size: CGSize(width: 420, height: 560), named: "new_thread_multiple_sources_worktree"
        )
    }

    func testScheduledTaskInEmptyProject() throws {
        let workspace = WorkspaceSnapshot(primarySource: nil)
        let fixture = try ScheduledTasksSnapshotFixture(includeTasks: false)
        var draft = fixture.viewModel.makeNewDraft()
        draft.projectID = "research"
        draft.workspaceSnapshot = workspace
        assertMacSnapshot(
            ScheduledTaskEditorWorkspaceSection(
                projects: [.init(path: "", name: "Research", id: "research", workspaceSnapshot: workspace)],
                threads: [], sections: [], draft: .constant(draft), onOpenReusedThread: { _ in }
            ).padding(24),
            size: CGSize(width: 760, height: 330), named: "scheduled_task_empty_project"
        )
    }

    func testProjectEditorEmptyProject() throws {
        let fixture = try SidebarTestFixture()
        assertMacSnapshot(
            ProjectEditorForm(viewModel: fixture.viewModel, configuration: ProjectConfiguration(name: "Research"),
                              onCancel: {}, onSaved: { _ in }).padding(24),
            size: CGSize(width: 580, height: 360), named: "project_editor_empty"
        )
    }

    func testProjectEditorMultipleFolders() throws {
        try assertProjectFolderEditor(colorScheme: .light, named: "project_editor_multiple")
    }

    func testProjectEditorMultipleFoldersDark() throws {
        try assertProjectFolderEditor(colorScheme: .dark, named: "project_editor_multiple_dark")
    }

    func testProjectFolderAddAreaHovered() {
        assertMacSnapshot(
            ProjectEditorAddFolderButton(isEmpty: true, action: {}, isHovered: true)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                .padding(24),
            size: CGSize(width: 580, height: 170), named: "project_add_folder_hovered", colorScheme: .dark
        )
    }

    func testProjectFolderAddRowHovered() {
        assertMacSnapshot(
            ProjectEditorAddFolderButton(isEmpty: false, action: {}, isHovered: true)
                .frame(height: 54).padding(24),
            size: CGSize(width: 580, height: 102), named: "project_add_folder_row_hovered", colorScheme: .dark
        )
    }

    func testProjectFoldersResolving() {
        for scheme in [ColorScheme.light, .dark] {
            for populated in [false, true] {
                let folders = populated ? projectFolderConfiguration.folders : []
                assertMacSnapshot(
                    ProjectEditorSourceFolders(
                        folders: folders, primaryFolderPath: folders.first?.path, isImporting: true,
                        onAdd: {}, onMakePrimary: { _ in }, onRemove: { _ in }
                    ).padding(24),
                    size: CGSize(width: 580, height: populated ? 330 : 170),
                    named: "project_folders_resolving_\(populated ? "populated" : "empty")_\(scheme)", colorScheme: scheme
                )
            }
        }
    }

    func testWorkspaceFolderMenuSelectsSecondary() {
        let folders = projectFolderConfiguration.folders.enumerated().map {
            WorkspaceFolderTarget(directory: $0.element.path, source: $0.element, isPrimary: $0.offset == 0)
        }
        assertMacSnapshot(
            WorkspaceFolderMenu(folders: folders, selected: folders[1], onSelect: { _ in })
                .labelStyle(.iconOnly).padding(20),
            size: CGSize(width: 280, height: 80), named: "workspace_folder_menu_secondary"
        )
    }

    private func assertProjectFolderEditor(colorScheme: ColorScheme, named name: String) throws {
        let fixture = try SidebarTestFixture()
        var configuration = projectFolderConfiguration
        configuration.primaryFolderPath = configuration.folders[1].path
        assertMacSnapshot(
            ProjectEditorSheet(projectID: "project", configuration: configuration, viewModel: fixture.viewModel),
            size: CGSize(width: 580, height: 530), named: name, colorScheme: colorScheme
        )
    }

    private var projectFolderConfiguration: ProjectConfiguration {
        ProjectConfiguration(name: "Alveary", folders: [
            SourceFolderSnapshot(path: "/Users/alice/Development/alveary", gitBranch: "main"),
            SourceFolderSnapshot(path: "/Users/alice/Development/AgentCLIKit", gitBranch: "main"),
            SourceFolderSnapshot(path: "/Users/alice/Documents/Design notes")
        ])
    }
}

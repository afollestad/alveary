import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testSidebarProjectsHeaderActionAlignsWithProjectRowAction() {
        let project = Project(path: "/tmp/alveary", name: "Alveary")
        let stack = VStack(spacing: 0) {
            SidebarSectionHeaderRow(title: "Projects", onAddProject: {})
            SidebarProjectRow(
                project: project,
                isExpanded: false,
                isSelected: true,
                onToggleExpanded: {},
                onActivate: {},
                onCreateThread: {}
            )
            .appSelectionRowBackground(isSelected: true)
        }

        assertMacSnapshot(
            stack,
            size: CGSize(width: 320, height: 92),
            named: "projects_header_project_action_alignment"
        )
    }

    func testSidebarViewNoProjectsKeepsAddProjectActionAligned() throws {
        let fixture = try SidebarTestFixture()

        assertMacSnapshot(
            SidebarView(viewModel: fixture.viewModel, appState: AppState())
                .modelContainer(fixture.container),
            size: CGSize(width: 320, height: 720),
            named: "sidebar_no_projects"
        )
    }

    func testSidebarViewSingleProjectWithoutThreadsKeepsAddProjectActionAligned() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/board-gridline-rush", name: "board-gridline-rush")
        fixture.context.insert(project)
        try fixture.context.save()

        let appState = AppState()
        appState.selectedSidebarItem = .project(project)

        assertMacSnapshot(
            SidebarView(viewModel: fixture.viewModel, appState: appState)
                .modelContainer(fixture.container),
            size: CGSize(width: 320, height: 260),
            named: "sidebar_single_project_no_threads"
        )
    }

    func testSidebarViewTwoProjectsWithoutThreadsKeepsAddProjectActionAligned() throws {
        let fixture = try SidebarTestFixture()
        let firstProject = Project(path: "/tmp/af.codes", name: "af.codes")
        let secondProject = Project(path: "/tmp/alveary", name: "alveary")
        fixture.context.insert(firstProject)
        fixture.context.insert(secondProject)
        try fixture.context.save()

        let appState = AppState()
        appState.selectedSidebarItem = .project(firstProject)

        assertMacSnapshot(
            SidebarView(viewModel: fixture.viewModel, appState: appState)
                .modelContainer(fixture.container),
            size: CGSize(width: 320, height: 340),
            named: "sidebar_two_projects_no_threads"
        )
    }
}

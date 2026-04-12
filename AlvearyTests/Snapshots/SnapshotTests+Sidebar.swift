import XCTest

@testable import Alveary

extension SnapshotTests {
    func testSidebarViewPopulated() async throws {
        let sidebar = try await makeSidebarSnapshotFixture()

        let appState = AppState()
        appState.selectedSidebarItem = .thread(sidebar.activeThread)

        assertMacSnapshot(
            SidebarView(viewModel: sidebar.fixture.viewModel, appState: appState)
                .modelContainer(sidebar.fixture.container),
            size: CGSize(width: 320, height: 720),
            named: "sidebar_populated"
        )
    }

    func testSidebarViewProjectSelected() async throws {
        let sidebar = try await makeSidebarSnapshotFixture()

        let appState = AppState()
        appState.selectedSidebarItem = .project(sidebar.project)

        assertMacSnapshot(
            SidebarView(viewModel: sidebar.fixture.viewModel, appState: appState)
                .modelContainer(sidebar.fixture.container),
            size: CGSize(width: 320, height: 720),
            named: "sidebar_project_selected"
        )
    }

    func testSidebarViewSkillsSelected() async throws {
        let sidebar = try await makeSidebarSnapshotFixture()

        let appState = AppState()
        appState.selectedSidebarItem = .skills

        assertMacSnapshot(
            SidebarView(viewModel: sidebar.fixture.viewModel, appState: appState)
                .modelContainer(sidebar.fixture.container),
            size: CGSize(width: 320, height: 720),
            named: "sidebar_skills_selected"
        )
    }
}

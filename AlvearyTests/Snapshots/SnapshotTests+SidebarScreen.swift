import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testSidebarViewPopulated() async throws {
        let sidebar = try await makeSidebarSnapshotFixture()

        let appState = AppState()
        appState.selectedSidebarItem = .thread(sidebar.activeThread)

        await assertMacModelSnapshot(modelContainer: sidebar.fixture.container,
            size: CGSize(width: 320, height: 720),
            named: "sidebar_populated"
        ) {
            SidebarView(viewModel: sidebar.fixture.viewModel, appState: appState)
        }
    }

    func testSidebarViewProjectSelected() async throws {
        let sidebar = try await makeSidebarSnapshotFixture()

        let appState = AppState()
        appState.selectedSidebarItem = .project(sidebar.project)

        await assertMacModelSnapshot(modelContainer: sidebar.fixture.container,
            size: CGSize(width: 320, height: 720),
            named: "sidebar_project_selected"
        ) {
            SidebarView(viewModel: sidebar.fixture.viewModel, appState: appState, initialExpandedProjects: [sidebar.project.path])
        }
    }

    func testSidebarViewPinnedThread() async throws {
        let sidebar = try await makeSidebarSnapshotFixture(includePinnedThread: true)

        let appState = AppState()
        appState.selectedSidebarItem = .project(sidebar.project)

        await assertMacModelSnapshot(modelContainer: sidebar.fixture.container,
            size: CGSize(width: 320, height: 720),
            named: "sidebar_pinned_thread"
        ) {
            SidebarView(viewModel: sidebar.fixture.viewModel, appState: appState, initialExpandedProjects: [sidebar.project.path])
        }
    }

    func testSidebarViewSelectedPinnedThread() async throws {
        let sidebar = try await makeSidebarSnapshotFixture(includePinnedThread: true)
        let pinnedThread = try XCTUnwrap(sidebar.pinnedThread)

        let appState = AppState()
        appState.selectedSidebarItem = .thread(pinnedThread)

        await assertMacModelSnapshot(modelContainer: sidebar.fixture.container,
            size: CGSize(width: 320, height: 720),
            named: "sidebar_selected_pinned_thread"
        ) {
            SidebarView(viewModel: sidebar.fixture.viewModel, appState: appState)
        }
    }

    func testSidebarViewMixedPinnedProjectAndThread() async throws {
        let sidebar = try await makeMixedPinnedSidebarSnapshotFixture()

        let appState = AppState()
        appState.selectedSidebarItem = .project(sidebar.pinnedProject)

        await assertMacModelSnapshot(modelContainer: sidebar.fixture.container,
            size: CGSize(width: 320, height: 720),
            named: "sidebar_mixed_pinned_project_and_thread"
        ) {
            SidebarView(viewModel: sidebar.fixture.viewModel, appState: appState, initialExpandedProjects: [sidebar.pinnedProject.path])
        }
    }

    func testSidebarViewExpandedProjectWithoutThreads() async throws {
        let sidebar = try await makeSidebarSnapshotFixture()

        let appState = AppState()
        appState.selectedSidebarItem = .project(sidebar.emptyProject)

        await assertMacModelSnapshot(modelContainer: sidebar.fixture.container,
            size: CGSize(width: 320, height: 720),
            named: "sidebar_project_no_threads"
        ) {
            SidebarView(viewModel: sidebar.fixture.viewModel, appState: appState, initialExpandedProjects: [sidebar.emptyProject.path])
        }
    }

    func testSidebarViewSkillsSelected() async throws {
        let sidebar = try await makeSidebarSnapshotFixture()

        let appState = AppState()
        appState.selectedSidebarItem = .skills

        await assertMacModelSnapshot(modelContainer: sidebar.fixture.container,
            size: CGSize(width: 320, height: 720),
            named: "sidebar_skills_selected"
        ) {
            SidebarView(viewModel: sidebar.fixture.viewModel, appState: appState)
        }
    }
}

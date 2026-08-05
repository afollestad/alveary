import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    // A collapsed header keeps its caret with the pointer away, so the section does not read as
    // empty. The `Projects` row below it is collapsed too, for the same reason.
    func testSidebarSectionHeaderCollapsedShowsCaretWithoutHover() {
        let project = Project(path: "/tmp/alveary", name: "Alveary")
        let stack = VStack(spacing: 0) {
            SidebarSectionHeaderRow(
                title: "Projects",
                disclosure: SidebarSectionHeaderDisclosure(isExpanded: false, onToggle: {}),
                onAddProject: {}
            )
            SidebarProjectRow(
                project: project,
                isExpanded: false,
                isSelected: false,
                onToggleExpanded: {},
                onActivate: {},
                onCreateThread: {}
            )
        }

        assertMacSnapshot(
            stack,
            size: CGSize(width: 320, height: 92),
            named: "section_header_collapsed_caret"
        )
    }

    func testSidebarSectionHeaderHoverExpandedShowsRotatedCaret() {
        assertMacSnapshot(
            SidebarSectionHeaderRow(
                title: "Projects",
                disclosure: SidebarSectionHeaderDisclosure(isExpanded: true, onToggle: {}),
                initialRowHover: true,
                onAddProject: {}
            ),
            size: CGSize(width: 320, height: 56),
            named: "section_header_hover_expanded_caret"
        )
    }

    // An expanded header hides its caret until the row is hovered, matching project rows.
    func testSidebarSectionHeaderExpandedHidesCaretWithoutHover() {
        assertMacSnapshot(
            SidebarSectionHeaderRow(
                title: "Projects",
                disclosure: SidebarSectionHeaderDisclosure(isExpanded: true, onToggle: {}),
                onAddProject: {}
            ),
            size: CGSize(width: 320, height: 56),
            named: "section_header_expanded_no_hover"
        )
    }

    // `Pinned` never collapses, so it reserves no caret slot at all.
    func testSidebarPinnedHeaderShowsNoCaret() {
        assertMacSnapshot(
            SidebarSectionHeaderRow(title: "Pinned", showsTopDivider: true),
            size: CGSize(width: 320, height: 56),
            named: "section_header_pinned_no_caret"
        )
    }

    func testSidebarProjectsSectionCollapsedHidesRowsAndKeepsTasks() async throws {
        let sidebar = try await makeSidebarSnapshotFixture()

        await assertMacModelSnapshot(
            modelContainer: sidebar.fixture.container,
            size: CGSize(width: 320, height: 720),
            named: "sidebar_projects_section_collapsed"
        ) {
            SidebarView(
                viewModel: sidebar.fixture.viewModel,
                appState: AppState(),
                initialExpandedProjects: [sidebar.project.path],
                initialCollapsedSections: [.projects]
            )
        }
    }

    func testSidebarTasksSectionCollapsedHidesTaskRows() async throws {
        let sidebar = try await makeTaskSidebarSnapshotFixture(
            activeNames: ["Rename worktree helper", "Sweep stale branches"]
        )

        await assertMacModelSnapshot(
            modelContainer: sidebar.fixture.container,
            size: CGSize(width: 320, height: 720),
            named: "sidebar_tasks_section_collapsed"
        ) {
            SidebarView(
                viewModel: sidebar.fixture.viewModel,
                appState: AppState(),
                initialCollapsedSections: [.tasks]
            )
        }
    }

    // With pinned items present the `Projects` header is an inline row rather than the list's
    // sticky section header, so it collapses through a different branch of `body`.
    func testSidebarProjectsSectionCollapsedBesidePinnedItems() async throws {
        let sidebar = try await makeMixedPinnedSidebarSnapshotFixture()

        await assertMacModelSnapshot(
            modelContainer: sidebar.fixture.container,
            size: CGSize(width: 320, height: 720),
            named: "sidebar_pinned_projects_section_collapsed"
        ) {
            SidebarView(
                viewModel: sidebar.fixture.viewModel,
                appState: AppState(),
                initialExpandedProjects: [sidebar.pinnedProject.path],
                initialCollapsedSections: [.projects]
            )
        }
    }
}

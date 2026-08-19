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
                projectName: project.name,
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

    // A collapsed section stands in for the row it hid: the waiting thread's blue dot moves onto
    // the header, trailing the caret.
    func testSidebarSectionHeaderCollapsedWaitingDot() {
        assertMacSnapshot(
            SidebarSectionHeaderRow(
                title: "Tasks",
                actionSystemImage: "plus",
                actionAccessibilityLabel: "New task",
                actionHelp: "New task",
                disclosure: SidebarSectionHeaderDisclosure(isExpanded: false, onToggle: {}),
                hidesWaitingThread: true,
                onAction: {}
            ),
            size: CGSize(width: 320, height: 56),
            named: "section_header_collapsed_waiting_dot"
        )
    }

    // A custom section reserves an invisible slot where the built-ins put their action button, so
    // its dot has to land in the same place against the title rather than drifting right.
    func testSidebarCustomSectionHeaderCollapsedWaitingDot() {
        assertMacSnapshot(
            SidebarSectionHeaderRow(
                title: "Review Queue",
                disclosure: SidebarSectionHeaderDisclosure(isExpanded: false, onToggle: {}),
                hidesWaitingThread: true
            ),
            size: CGSize(width: 320, height: 56),
            named: "section_header_custom_collapsed_waiting_dot"
        )
    }

    // Stacked with no spacing, so a dot that grew the header or sat off the title's optical centre
    // shows up as misalignment between the two titles.
    func testSidebarSectionHeadersWithAndWithoutWaitingDotShareHeight() {
        let stack = VStack(spacing: 0) {
            SidebarSectionHeaderRow(
                title: "Tasks",
                disclosure: SidebarSectionHeaderDisclosure(isExpanded: false, onToggle: {}),
                hidesWaitingThread: true
            )
            SidebarSectionHeaderRow(
                title: "Tasks",
                disclosure: SidebarSectionHeaderDisclosure(isExpanded: false, onToggle: {})
            )
        }

        assertMacSnapshot(
            stack,
            size: CGSize(width: 320, height: 92),
            named: "section_headers_waiting_dot_height_parity"
        )
    }

    // A long custom section name truncates rather than wrapping, so the dot cannot push the
    // header onto a second line. Stacked at a width that forces truncation: both rows must stay
    // one line tall and share a height.
    func testSidebarLongSectionNameStaysSingleLineWithWaitingDot() {
        let long = "Release Notes And Changelog Review Queue"
        let stack = VStack(spacing: 0) {
            SidebarSectionHeaderRow(
                title: long,
                disclosure: SidebarSectionHeaderDisclosure(isExpanded: false, onToggle: {}),
                hidesWaitingThread: true
            )
            SidebarSectionHeaderRow(
                title: long,
                disclosure: SidebarSectionHeaderDisclosure(isExpanded: false, onToggle: {})
            )
        }

        assertMacSnapshot(
            stack,
            size: CGSize(width: 240, height: 92),
            named: "section_header_long_name_single_line"
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

import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testSidebarProjectRowHoverCollapsedShowsRightChevron() {
        let project = Project(path: "/tmp/alveary", name: "Alveary")

        assertMacSnapshot(
            SidebarProjectRow(
                project: project,
                isExpanded: false,
                isSelected: false,
                initialRowHover: true,
                initialToggleIconHover: true,
                onToggleExpanded: {},
                onActivate: {},
                onCreateThread: {}
            ),
            size: CGSize(width: 280, height: 52),
            named: "project_row_hover_collapsed_chevron"
        )
    }

    func testSidebarProjectRowHoverExpandedShowsDownChevron() {
        let project = Project(path: "/tmp/alveary", name: "Alveary")

        assertMacSnapshot(
            SidebarProjectRow(
                project: project,
                isExpanded: true,
                isSelected: false,
                initialRowHover: true,
                initialToggleIconHover: true,
                onToggleExpanded: {},
                onActivate: {},
                onCreateThread: {}
            ),
            size: CGSize(width: 280, height: 52),
            named: "project_row_hover_expanded_chevron"
        )
    }

    func testSidebarProjectRowSelectedCollapsedKeepsFolderIcon() {
        let project = Project(path: "/tmp/alveary", name: "Alveary")

        assertMacSnapshot(
            SidebarProjectRow(
                project: project,
                isExpanded: false,
                isSelected: true,
                onToggleExpanded: {},
                onActivate: {},
                onCreateThread: {}
            )
            .appSelectionRowBackground(isSelected: true),
            size: CGSize(width: 280, height: 52),
            named: "project_row_selected_collapsed_folder"
        )
    }

    func testSidebarProjectRowSelectedExpandedKeepsFolderIcon() {
        let project = Project(path: "/tmp/alveary", name: "Alveary")

        assertMacSnapshot(
            SidebarProjectRow(
                project: project,
                isExpanded: true,
                isSelected: true,
                onToggleExpanded: {},
                onActivate: {},
                onCreateThread: {}
            )
            .appSelectionRowBackground(isSelected: true),
            size: CGSize(width: 280, height: 52),
            named: "project_row_selected_expanded_folder"
        )
    }

    func testSidebarThreadRowStoppedStatusDotVisible() {
        let thread = AgentThread(name: AgentThread.untitledName)

        assertMacSnapshot(
            SidebarThreadRow(
                thread: thread,
                status: .stopped,
                isSelected: false,
                editingThreadID: .constant(nil),
                onCommitRename: { _ in }
            )
            .padding(.leading, 14),
            size: CGSize(width: 280, height: 52),
            named: "thread_row_stopped_dot"
        )
    }

    func testSidebarThreadRowHoverShowsArchiveCleanupButton() {
        let thread = AgentThread(name: AgentThread.untitledName)

        assertMacSnapshot(
            SidebarThreadRow(
                thread: thread,
                status: .stopped,
                isSelected: false,
                editingThreadID: .constant(nil),
                cleanupAction: .archive,
                initialRowHover: true,
                onCommitRename: { _ in }
            )
            .padding(.leading, 14),
            size: CGSize(width: 280, height: 52),
            named: "thread_row_hover_archive_cleanup"
        )
    }

    func testSidebarThreadRowHoverShowsDeleteCleanupButton() {
        let thread = AgentThread(name: AgentThread.untitledName)

        assertMacSnapshot(
            SidebarThreadRow(
                thread: thread,
                status: .stopped,
                isSelected: false,
                editingThreadID: .constant(nil),
                cleanupAction: .delete,
                initialRowHover: true,
                onCommitRename: { _ in }
            )
            .padding(.leading, 14),
            size: CGSize(width: 280, height: 52),
            named: "thread_row_hover_delete_cleanup"
        )
    }

    func testSidebarThreadRowCleanupConfirmationExpandsLeft() {
        let thread = AgentThread(name: AgentThread.untitledName)

        assertMacSnapshot(
            SidebarThreadRow(
                thread: thread,
                status: .stopped,
                isSelected: false,
                editingThreadID: .constant(nil),
                cleanupAction: .delete,
                initialCleanupConfirmationArmed: true,
                onCommitRename: { _ in }
            )
            .padding(.leading, 14),
            size: CGSize(width: 280, height: 52),
            named: "thread_row_cleanup_confirm"
        )
    }

    func testSidebarThreadRowCleanupConfirmationEllipsizesLongTitle() {
        let thread = AgentThread(name: "Investigate the very long thread cleanup confirmation layout")

        assertMacSnapshot(
            SidebarThreadRow(
                thread: thread,
                status: .stopped,
                isSelected: false,
                editingThreadID: .constant(nil),
                cleanupAction: .delete,
                initialCleanupConfirmationArmed: true,
                onCommitRename: { _ in }
            )
            .padding(.leading, 14),
            size: CGSize(width: 260, height: 52),
            named: "thread_row_cleanup_confirm_long_title"
        )
    }

    // Pins `.busy` to the fixed-size spinner; no other sidebar snapshot exercises `.busy`.
    func testSidebarThreadRowBusyStatusSpinnerVisible() {
        let thread = AgentThread(name: AgentThread.untitledName)

        assertMacSnapshot(
            SidebarThreadRow(
                thread: thread,
                status: .busy,
                isSelected: false,
                editingThreadID: .constant(nil),
                onCommitRename: { _ in }
            )
            .padding(.leading, 14),
            size: CGSize(width: 280, height: 52),
            named: "thread_row_busy_spinner"
        )
    }

    func testSidebarThreadRowWaitingForUserStatusDotVisible() {
        let thread = AgentThread(name: AgentThread.untitledName)

        assertMacSnapshot(
            SidebarThreadRow(
                thread: thread,
                status: .waitingForUser,
                isSelected: false,
                editingThreadID: .constant(nil),
                onCommitRename: { _ in }
            )
            .padding(.leading, 14),
            size: CGSize(width: 280, height: 52),
            named: "thread_row_waiting_for_user_dot"
        )
    }

    func testSidebarThreadRowInlineCodeTitle() {
        let thread = AgentThread(name: "Test `code block`")

        assertMacSnapshot(
            SidebarThreadRow(
                thread: thread,
                status: .unread,
                isSelected: false,
                editingThreadID: .constant(nil),
                onCommitRename: { _ in }
            )
            .padding(.leading, 14),
            size: CGSize(width: 320, height: 52),
            named: "thread_row_inline_code"
        )
    }

    func testSidebarThreadRowMarkdownLinkTitle() {
        let thread = AgentThread(name: "[.alveary.json](.alveary.json)")

        assertMacSnapshot(
            SidebarThreadRow(
                thread: thread,
                status: .unread,
                isSelected: false,
                editingThreadID: .constant(nil),
                onCommitRename: { _ in }
            )
            .padding(.leading, 14),
            size: CGSize(width: 320, height: 52),
            named: "thread_row_markdown_link"
        )
    }

    // Dark-mode coverage for the `.standard` chip palette. `AppMarkdownCodeBlockPalette`
    // uses a theme-aware grayscale `inlineFillNSColor`, so this locks in how the chip
    // reads on a dark sidebar.
    func testSidebarThreadRowInlineCodeTitleDark() {
        let thread = AgentThread(name: "Test `code block`")

        assertMacSnapshot(
            SidebarThreadRow(
                thread: thread,
                status: .unread,
                isSelected: false,
                editingThreadID: .constant(nil),
                onCommitRename: { _ in }
            )
            .padding(.leading, 14),
            size: CGSize(width: 320, height: 52),
            named: "thread_row_inline_code_dark",
            colorScheme: .dark
        )
    }

    func testSidebarThreadRowSelectedInlineCodeUsesOnAccentChipStyle() {
        let thread = AgentThread(name: "Test `code block`")

        // Render the row over an `AppAccentFill.primary` background so the snapshot
        // captures how the chip reads against a selected-row's accent-tinted parent.
        // `AppMarkdownInlineLabel` always renders the `.standard` chip palette, so the
        // chip keeps its gray fill regardless of row selection — this baseline locks in
        // the uniform-across-selection behavior.
        assertMacSnapshot(
            SidebarThreadRow(
                thread: thread,
                status: .unread,
                isSelected: true,
                editingThreadID: .constant(nil),
                onCommitRename: { _ in }
            )
            .padding(.leading, 14)
            .background(AppAccentFill.primary),
            size: CGSize(width: 320, height: 52),
            named: "thread_row_selected_inline_code"
        )
    }

    // Dark-mode coverage for the selected-row chip treatment. Sidebar thread rows keep
    // the `.standard` grayscale chip fill for both selected and unselected states; this
    // baseline locks in how that gray reads against a dark-mode accent-tinted
    // `AppAccentFill.primary`.
    func testSidebarThreadRowSelectedInlineCodeUsesOnAccentChipStyleDark() {
        let thread = AgentThread(name: "Test `code block`")

        assertMacSnapshot(
            SidebarThreadRow(
                thread: thread,
                status: .unread,
                isSelected: true,
                editingThreadID: .constant(nil),
                onCommitRename: { _ in }
            )
            .padding(.leading, 14)
            .background(AppAccentFill.primary),
            size: CGSize(width: 320, height: 52),
            named: "thread_row_selected_inline_code_dark",
            colorScheme: .dark
        )
    }

    func testSidebarThreadRowCodeOnlyTitleRendersChip() {
        let thread = AgentThread(name: "`code only`")

        assertMacSnapshot(
            SidebarThreadRow(
                thread: thread,
                status: .unread,
                isSelected: false,
                editingThreadID: .constant(nil),
                onCommitRename: { _ in }
            )
            .padding(.leading, 14),
            size: CGSize(width: 320, height: 52),
            named: "thread_row_code_only"
        )
    }

    func testSidebarThreadRowMentionTitleRendersChip() {
        let thread = AgentThread(name: "@.alveary.json")

        assertMacSnapshot(
            SidebarThreadRow(
                thread: thread,
                status: .unread,
                isSelected: false,
                editingThreadID: .constant(nil),
                onCommitRename: { _ in }
            )
            .padding(.leading, 14),
            size: CGSize(width: 320, height: 52),
            named: "thread_row_mention_only"
        )
    }

    func testSidebarThreadRowLongMentionTitleStaysBounded() {
        let thread = AgentThread(name: "@ai-rules-generated-watermark-portfolio-images")

        assertMacSnapshot(
            SidebarThreadRow(
                thread: thread,
                status: .stopped,
                isSelected: true,
                editingThreadID: .constant(nil),
                onCommitRename: { _ in }
            )
            .padding(.leading, 14)
            .background(AppAccentFill.primary),
            size: CGSize(width: 320, height: 52),
            named: "thread_row_long_mention_bounded"
        )
    }

    func testSidebarThreadRowChipAndPlainShareHeight() {
        let plainThread = AgentThread(name: "New thread")
        let chipThread = AgentThread(name: "Test `code block`")

        let stack = VStack(spacing: 0) {
            SidebarThreadRow(
                thread: plainThread,
                status: .unread,
                isSelected: false,
                editingThreadID: .constant(nil),
                onCommitRename: { _ in }
            )
            SidebarThreadRow(
                thread: chipThread,
                status: .unread,
                isSelected: false,
                editingThreadID: .constant(nil),
                onCommitRename: { _ in }
            )
        }
        .padding(.leading, 14)

        assertMacSnapshot(
            stack,
            size: CGSize(width: 320, height: 80),
            named: "thread_rows_chip_plain_stack"
        )
    }

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

    func testSidebarViewExpandedProjectWithoutThreads() async throws {
        let sidebar = try await makeSidebarSnapshotFixture()

        let appState = AppState()
        appState.selectedSidebarItem = .project(sidebar.emptyProject)

        assertMacSnapshot(
            SidebarView(viewModel: sidebar.fixture.viewModel, appState: appState)
                .modelContainer(sidebar.fixture.container),
            size: CGSize(width: 320, height: 720),
            named: "sidebar_project_no_threads"
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

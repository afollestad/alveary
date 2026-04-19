import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
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

    // Dark-mode coverage for the `.standard` chip palette. `AppMarkdownCodeBlockPalette`
    // derives `inlineFillNSColor` from `NSColor.controlAccentColor` (shared with assistant
    // bubble inline code), so this locks in how the chip reads on a dark sidebar.
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

        // Render the row over an `AppSelectionStyle.rowFill` background so the snapshot
        // captures the on-accent-surface chip styling that `isSelected: true` activates.
        // A standard-palette chip on a rowFill background would be accent-on-accent and
        // wash out; this baseline locks in the `.userBubble` chip palette switch.
        assertMacSnapshot(
            SidebarThreadRow(
                thread: thread,
                status: .unread,
                isSelected: true,
                editingThreadID: .constant(nil),
                onCommitRename: { _ in }
            )
            .padding(.leading, 14)
            .background(AppSelectionStyle.rowFill),
            size: CGSize(width: 320, height: 52),
            named: "thread_row_selected_inline_code"
        )
    }

    // Dark-mode coverage for the `.userBubble` chip palette on a selected row. Locks in
    // the grayscale chip fill (`userBubbleInlineFillNSColor`) that contrasts against the
    // accent-tinted `rowFill` in dark mode.
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
            .background(AppSelectionStyle.rowFill),
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

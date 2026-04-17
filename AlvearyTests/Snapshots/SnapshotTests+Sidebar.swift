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
                editingThreadID: .constant(nil),
                onCommitRename: { _ in }
            )
            .padding(.leading, 14),
            size: CGSize(width: 320, height: 52),
            named: "thread_row_inline_code"
        )
    }

    func testSidebarThreadRowCodeOnlyTitleRendersChip() {
        let thread = AgentThread(name: "`code only`")

        assertMacSnapshot(
            SidebarThreadRow(
                thread: thread,
                status: .unread,
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
                editingThreadID: .constant(nil),
                onCommitRename: { _ in }
            )
            SidebarThreadRow(
                thread: chipThread,
                status: .unread,
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

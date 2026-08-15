import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testSidebarThreadRowWorktreeIndicatorVisible() {
        let thread = AgentThread(
            name: "Refactor Chat Input",
            worktreePath: "/tmp/alveary-worktrees/refactor-chat-input",
            useWorktree: true
        )

        assertMacSnapshot(
            SidebarThreadRow(
                presentation: SidebarThreadRowPresentation(thread: thread),
                status: .stopped,
                isSelected: false,
                onCommitRename: { _ in }
            )
            .padding(.leading, 14),
            size: CGSize(width: 280, height: 52),
            named: "thread_row_worktree_indicator"
        )
    }

    func testSidebarThreadRowWorktreeLongTitleStaysLeftOfIndicator() {
        let thread = AgentThread(
            name: "Investigate the extremely long worktree thread indicator layout that must ellipsize before the branch glyph",
            worktreePath: "/tmp/alveary-worktrees/worktree-indicator-layout",
            useWorktree: true
        )

        assertMacSnapshot(
            SidebarThreadRow(
                presentation: SidebarThreadRowPresentation(thread: thread),
                status: .stopped,
                isSelected: false,
                onCommitRename: { _ in }
            )
            .padding(.leading, 14),
            size: CGSize(width: 260, height: 52),
            named: "thread_row_worktree_long_title"
        )
    }

    func testSidebarThreadRowWorktreeLongTitleHoverKeepsTitleWidthStable() {
        let thread = AgentThread(
            name: "Investigate the extremely long worktree thread indicator layout that must ellipsize before the branch glyph",
            worktreePath: "/tmp/alveary-worktrees/worktree-indicator-layout",
            useWorktree: true
        )

        assertMacSnapshot(
            SidebarThreadRow(
                presentation: SidebarThreadRowPresentation(thread: thread),
                status: .stopped,
                isSelected: false,
                cleanupAction: .archive,
                initialRowHover: true,
                onCommitRename: { _ in }
            )
            .padding(.leading, 14),
            size: CGSize(width: 260, height: 52),
            named: "thread_row_worktree_long_title_hover"
        )
    }

    func testSidebarThreadRowSelectedWorktreeIndicatorVisible() {
        let thread = AgentThread(
            name: "Refactor Chat Input",
            worktreePath: "/tmp/alveary-worktrees/refactor-chat-input",
            useWorktree: true
        )

        assertMacSnapshot(
            SidebarThreadRow(
                presentation: SidebarThreadRowPresentation(thread: thread),
                status: .stopped,
                isSelected: true,
                onCommitRename: { _ in }
            )
            .padding(.leading, 14)
            .background(AppAccentFill.primary),
            size: CGSize(width: 280, height: 52),
            named: "thread_row_selected_worktree_indicator"
        )
    }

    func testSidebarThreadRowWorktreeHoverCleanupIconKeepsIndicatorStable() {
        let thread = AgentThread(
            name: "Refactor Chat Input",
            worktreePath: "/tmp/alveary-worktrees/refactor-chat-input",
            useWorktree: true
        )

        assertMacSnapshot(
            SidebarThreadRow(
                presentation: SidebarThreadRowPresentation(thread: thread),
                status: .stopped,
                isSelected: false,
                cleanupAction: .archive,
                initialRowHover: true,
                onCommitRename: { _ in }
            )
            .padding(.leading, 14),
            size: CGSize(width: 280, height: 52),
            named: "thread_row_worktree_hover_cleanup"
        )
    }

    func testSidebarThreadRowSelectedWorktreeHoverCleanupIconKeepsIndicatorStable() {
        let thread = AgentThread(
            name: "Refactor Chat Input",
            worktreePath: "/tmp/alveary-worktrees/refactor-chat-input",
            useWorktree: true
        )

        assertMacSnapshot(
            SidebarThreadRow(
                presentation: SidebarThreadRowPresentation(thread: thread),
                status: .stopped,
                isSelected: true,
                cleanupAction: .delete,
                initialRowHover: true,
                onCommitRename: { _ in }
            )
            .padding(.leading, 14)
            .background(AppAccentFill.primary),
            size: CGSize(width: 280, height: 52),
            named: "thread_row_selected_worktree_hover_cleanup"
        )
    }

    func testSidebarThreadRowWorktreeCleanupConfirmationExpandsLeft() {
        let thread = AgentThread(
            name: "Refactor Chat Input",
            worktreePath: "/tmp/alveary-worktrees/refactor-chat-input",
            useWorktree: true
        )

        assertMacSnapshot(
            SidebarThreadRow(
                presentation: SidebarThreadRowPresentation(thread: thread),
                status: .stopped,
                isSelected: false,
                cleanupAction: .delete,
                initialCleanupConfirmationArmed: true,
                onCommitRename: { _ in }
            )
            .padding(.leading, 14),
            size: CGSize(width: 280, height: 52),
            named: "thread_row_worktree_cleanup_confirm"
        )
    }
}

import Foundation
import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testSidebarThreadRowScheduledIndicatorVisible() {
        let thread = scheduledSidebarThread()

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
            named: "thread_row_scheduled_indicator"
        )
    }

    func testSidebarThreadRowScheduledAndWorktreeIndicatorsUseProvenanceOrder() {
        let thread = scheduledSidebarThread(
            worktreePath: "/tmp/alveary-worktrees/scheduled-review",
            useWorktree: true
        )

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
            named: "thread_row_scheduled_worktree_indicators"
        )
    }

    func testSidebarThreadRowScheduledAndWorktreeIndicatorsStayBeforeCleanup() {
        let thread = scheduledSidebarThread(
            worktreePath: "/tmp/alveary-worktrees/scheduled-review",
            useWorktree: true
        )

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
            named: "thread_row_scheduled_worktree_hover_cleanup"
        )
    }

    func testSidebarViewScheduledSelected() async throws {
        let sidebar = try await makeSidebarSnapshotFixture()
        let appState = AppState()
        appState.selectedSidebarItem = .scheduled

        assertMacSnapshot(
            SidebarView(viewModel: sidebar.fixture.viewModel, appState: appState)
                .modelContainer(sidebar.fixture.container),
            size: CGSize(width: 320, height: 720),
            named: "sidebar_scheduled_selected"
        )
    }
}

private func scheduledSidebarThread(worktreePath: String? = nil, useWorktree: Bool = false) -> AgentThread {
    let run = ScheduledTaskRun(
        occurrenceID: "sidebar-snapshot-occurrence",
        definitionID: "sidebar-snapshot-definition",
        definitionRevision: 1,
        occurrenceAt: Date(timeIntervalSince1970: 1_800_000_000),
        triggerKind: .scheduled,
        status: .success,
        titleSnapshot: "Scheduled review",
        promptSnapshot: "Review the workspace.",
        timeZoneIdentifierSnapshot: "America/Chicago",
        providerIDSnapshot: "codex",
        effortSnapshot: "high",
        permissionModeSnapshot: "default",
        workspaceKindSnapshot: .project,
        workspaceStrategySnapshot: useWorktree ? .worktree : .localCheckout
    )
    let thread = AgentThread(
        name: "Scheduled review",
        worktreePath: worktreePath,
        useWorktree: useWorktree,
        mode: .task,
        scheduledTaskRun: run
    )
    run.thread = thread
    return thread
}

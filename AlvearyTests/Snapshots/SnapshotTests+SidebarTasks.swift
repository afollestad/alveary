import SwiftUI

@testable import Alveary

extension SnapshotTests {
    func testSidebarViewMixedPinnedProjectThreadAndTask() async throws {
        let sidebar = try await makeMixedPinnedSidebarSnapshotFixture()
        sidebar.pinnedProject.pinnedSortOrder = 0
        sidebar.standalonePinnedThread.pinnedSortOrder = 1
        let task = AgentThread(
            name: "Pinned Task",
            isPinned: true,
            pinnedSortOrder: 2,
            modifiedAt: Date(timeIntervalSince1970: 1_713_000_050),
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/sidebar-mixed-pinned-task",
                ownershipStrategy: .projectLocal
            )
        )
        let conversation = Conversation(
            id: "mixed-pinned-task",
            title: "Main",
            provider: "claude",
            thread: task
        )
        task.conversations = [conversation]
        sidebar.fixture.context.insert(task)
        sidebar.fixture.context.insert(conversation)
        try sidebar.fixture.context.save()
        await sidebar.fixture.agentsManager.setStatus(.idle, for: conversation.id)

        assertMacSnapshot(
            SidebarView(viewModel: sidebar.fixture.viewModel, appState: AppState())
                .modelContainer(sidebar.fixture.container),
            size: CGSize(width: 360, height: 720),
            named: "sidebar_mixed_pinned_project_thread_task"
        )
    }

    func testSidebarViewEmptyTasksWide() async throws {
        let sidebar = try await makeTaskSidebarSnapshotFixture()

        assertMacSnapshot(
            SidebarView(viewModel: sidebar.fixture.viewModel, appState: AppState())
                .modelContainer(sidebar.fixture.container),
            size: CGSize(width: 360, height: 720),
            named: "sidebar_tasks_empty_wide"
        )
    }

    func testSidebarViewAllTasksPinnedDark() async throws {
        let sidebar = try await makeTaskSidebarSnapshotFixture(pinnedNames: ["Pinned task", "Another pinned task"])
        let appState = AppState()
        appState.selectedSidebarItem = sidebar.tasks.first.map(SidebarItem.thread)

        assertMacSnapshot(
            SidebarView(viewModel: sidebar.fixture.viewModel, appState: appState)
                .modelContainer(sidebar.fixture.container),
            size: CGSize(width: 320, height: 720),
            named: "sidebar_tasks_all_pinned_dark",
            colorScheme: .dark
        )
    }

    func testSidebarViewMixedTasksNarrow() async throws {
        let sidebar = try await makeTaskSidebarSnapshotFixture(
            pinnedNames: ["Pinned audit"],
            activeNames: ["Newest task", "Older task"]
        )

        assertMacSnapshot(
            SidebarView(viewModel: sidebar.fixture.viewModel, appState: AppState())
                .modelContainer(sidebar.fixture.container),
            size: CGSize(width: 240, height: 720),
            named: "sidebar_tasks_mixed_narrow"
        )
    }

    func testSidebarViewLongTaskRowsWide() async throws {
        let sidebar = try await makeTaskSidebarSnapshotFixture(activeNames: [
            "Review the extraordinarily long natural-language scheduled task configuration and workspace grants"
        ])

        assertMacSnapshot(
            SidebarView(viewModel: sidebar.fixture.viewModel, appState: AppState())
                .modelContainer(sidebar.fixture.container),
            size: CGSize(width: 360, height: 720),
            named: "sidebar_tasks_long_row_wide"
        )
    }
}

import SwiftData
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testScheduledTasksScreenEmpty() throws {
        let fixture = try ScheduledTasksSnapshotFixture(includeTasks: false)

        assertMacSnapshot(
            ScheduledTasksScreen(viewModel: fixture.viewModel),
            size: CGSize(width: 1_120, height: 900),
            named: "scheduled_tasks_empty"
        )
    }

    func testScheduledTasksScreenPopulated() throws {
        let fixture = try ScheduledTasksSnapshotFixture()

        assertMacSnapshot(
            ScheduledTasksScreen(viewModel: fixture.viewModel),
            size: CGSize(width: 1_120, height: 900),
            named: "scheduled_tasks_populated"
        )
    }

    func testScheduledTasksScreenPopulatedDark() throws {
        let fixture = try ScheduledTasksSnapshotFixture()

        assertMacSnapshot(
            ScheduledTasksScreen(viewModel: fixture.viewModel),
            size: CGSize(width: 1_120, height: 900),
            named: "scheduled_tasks_populated_dark",
            colorScheme: .dark
        )
    }

    func testScheduledTasksScreenPopulatedNarrow() throws {
        let fixture = try ScheduledTasksSnapshotFixture()

        assertMacSnapshot(
            ScheduledTasksScreen(viewModel: fixture.viewModel),
            size: CGSize(width: 640, height: 900),
            named: "scheduled_tasks_populated_narrow"
        )
    }
    func testScheduledTaskEditorWeekdaySelection() throws {
        let fixture = try ScheduledTasksSnapshotFixture(includeTasks: false)
        var draft = fixture.viewModel.makeNewDraft()
        draft.recurrenceKind = .weekdays

        assertMacSnapshot(
            ScheduledTaskEditorSheet(
                viewModel: fixture.viewModel,
                initialDraft: draft,
                onClose: {}
            ),
            size: CGSize(width: 760, height: 780),
            named: "scheduled_task_editor_weekday_selection"
        )
    }
}

@MainActor
private final class ScheduledTasksSnapshotFixture {
    let container: ModelContainer
    let viewModel: ScheduledTasksViewModel

    init(includeTasks: Bool = true) throws {
        container = try Self.makeContainer()
        let context = ModelContext(container)
        let notificationCenter = NotificationCenter()
        if includeTasks {
            try Self.insertFixtures(into: context)
        }
        let mutationService = ScheduledTaskMutationService(
            modelContext: context,
            notificationCenter: notificationCenter
        )
        viewModel = ScheduledTasksViewModel(
            modelContext: context,
            mutationService: mutationService,
            settingsService: InMemorySettingsService(),
            notificationCenter: notificationCenter,
            runNow: { _ in true },
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }

    private static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private static func insertFixtures(into context: ModelContext) throws {
        let project = Project(path: "/tmp/alveary-snapshot", name: "Alveary")
        context.insert(project)
        context.insert(activeTask(project: project))
        context.insert(pausedTask())
        context.insert(completedTask())
        try context.save()
    }

    private static func activeTask(project: Project) -> ScheduledTask {
        ScheduledTask(
            id: "active-snapshot",
            title: "Review open pull requests",
            prompt: "Summarize open pull requests, identify risks, and recommend the next review.",
            state: .active,
            recurrence: .weekdays(hour: 9, minute: 0),
            timeZoneIdentifier: "America/Chicago",
            providerID: "codex",
            model: nil,
            effort: "medium",
            permissionMode: "on-request",
            workspaceKind: .project,
            workspaceStrategy: .worktree,
            project: project,
            nextOccurrenceAt: Date(timeIntervalSince1970: 1_800_036_000),
            modifiedAt: Date(timeIntervalSince1970: 300)
        )
    }

    private static func pausedTask() -> ScheduledTask {
        ScheduledTask(
            id: "paused-snapshot",
            title: "Refresh release notes",
            prompt: "Update the release notes from completed work and call out user-visible changes.",
            state: .paused,
            recurrence: .weekly(weekday: 6, hour: 15, minute: 30),
            timeZoneIdentifier: "America/Los_Angeles",
            providerID: "claude",
            workspaceKind: .privateWorkspace,
            workspaceStrategy: .worktree,
            grantedRoots: ["/tmp/release-assets"],
            nextOccurrenceAt: Date(timeIntervalSince1970: 1_800_122_400),
            pauseReason: "Claude needs setup before this task can run.",
            modifiedAt: Date(timeIntervalSince1970: 200)
        )
    }

    private static func completedTask() -> ScheduledTask {
        ScheduledTask(
            id: "completed-snapshot",
            title: "Prepare launch checklist",
            prompt: "Prepare the launch checklist for the scheduled release.",
            state: .completed,
            recurrence: .once(Date(timeIntervalSince1970: 1_799_900_000)),
            timeZoneIdentifier: "UTC",
            providerID: "codex",
            workspaceKind: .privateWorkspace,
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
    }
}

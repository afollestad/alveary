import SwiftData
import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testScheduledTaskCreatePaneAtMinimumWidth() throws {
        let fixture = try ScheduledTasksSnapshotFixture(includeTasks: false)
        fixture.viewModel.requestCreate()

        assertMacSnapshot(
            ScheduledTaskEditorPane(viewModel: fixture.viewModel),
            size: CGSize(width: 320, height: 780),
            named: "scheduled_task_create_pane_minimum_width"
        )
    }

    func testScheduledTaskEditPaneAtMinimumWidth() throws {
        let fixture = try ScheduledTasksSnapshotFixture()
        let task = try XCTUnwrap(fixture.viewModel.tasks.first)
        fixture.viewModel.requestEdit(definitionID: task.id)

        assertMacSnapshot(
            ScheduledTaskEditorPane(viewModel: fixture.viewModel),
            size: CGSize(width: 320, height: 780),
            named: "scheduled_task_edit_pane_minimum_width"
        )
    }

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

    func testScheduledTasksFilterChipsActiveSelection() {
        assertMacSnapshot(
            ScheduledTasksScreenHeader(
                selectedFilter: .constant(.active),
                onCreate: {}
            ),
            size: CGSize(width: 640, height: 72),
            named: "scheduled_tasks_filter_chips_active"
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

    func testScheduledTaskDeleteProposalOverlay() throws {
        let fixture = try ScheduledTaskProposalSnapshotFixture()

        assertMacSnapshot(
            ScheduledTaskProposalOverlay(
                proposal: fixture.proposal,
                coordinator: fixture.coordinator,
                scheduledTasksViewModel: fixture.viewModel
            ),
            size: CGSize(width: 900, height: 680),
            named: "scheduled_task_delete_proposal"
        )
    }

    func testScheduledTaskDeleteProposalOverlayDark() throws {
        let fixture = try ScheduledTaskProposalSnapshotFixture()

        assertMacSnapshot(
            ScheduledTaskProposalOverlay(
                proposal: fixture.proposal,
                coordinator: fixture.coordinator,
                scheduledTasksViewModel: fixture.viewModel
            ),
            size: CGSize(width: 900, height: 680),
            named: "scheduled_task_delete_proposal_dark",
            colorScheme: .dark
        )
    }

    func testScheduledTaskEditorProposalOverlayError() throws {
        let fixture = try ScheduledTaskProposalSnapshotFixture()
        fixture.coordinator.errorMessage = "The proposal could not be rejected because its pending confirmation could not be saved."

        assertMacSnapshot(
            ScheduledTaskProposalOverlay(
                proposal: fixture.editorProposal,
                coordinator: fixture.coordinator,
                scheduledTasksViewModel: fixture.viewModel
            ),
            size: CGSize(width: 900, height: 780),
            named: "scheduled_task_editor_proposal_error"
        )
    }

    func testScheduledTaskEditorProposalOverlayNarrow() throws {
        let fixture = try ScheduledTaskProposalSnapshotFixture()

        assertMacSnapshot(
            ScheduledTaskProposalOverlay(
                proposal: fixture.editorProposal,
                coordinator: fixture.coordinator,
                scheduledTasksViewModel: fixture.viewModel
            ),
            size: CGSize(width: 640, height: 780),
            named: "scheduled_task_editor_proposal_narrow"
        )
    }

    func testScheduledTaskIntervalProposalOverlay() throws {
        let fixture = try ScheduledTaskProposalSnapshotFixture()

        assertMacSnapshot(
            ScheduledTaskProposalOverlay(
                proposal: fixture.intervalEditorProposal,
                coordinator: fixture.coordinator,
                scheduledTasksViewModel: fixture.viewModel
            ),
            size: CGSize(width: 1_200, height: 768),
            named: "scheduled_task_interval_proposal"
        )
    }

    func testScheduledTaskIntervalProposalOverlayDark() throws {
        let fixture = try ScheduledTaskProposalSnapshotFixture()

        assertMacSnapshot(
            ScheduledTaskProposalOverlay(
                proposal: fixture.intervalEditorProposal,
                coordinator: fixture.coordinator,
                scheduledTasksViewModel: fixture.viewModel
            ),
            size: CGSize(width: 1_200, height: 768),
            named: "scheduled_task_interval_proposal_dark",
            colorScheme: .dark
        )
    }
}

@MainActor
private final class ScheduledTaskProposalSnapshotFixture {
    let proposal = ScheduledTaskProposalPresentation(
        id: "proposal-delete-snapshot",
        action: .delete,
        sourceConversationID: "proposal-source",
        targetDefinitionID: "proposal-target",
        expectedDefinitionRevision: 3,
        targetTitle: "Review open pull requests",
        targetScheduleSummary: "Weekdays at 9:00 AM [America/Chicago]",
        definitionDraft: nil,
        createdAt: Date(timeIntervalSince1970: 1_800_000_000),
        conflictMessage: nil
    )
    let editorProposal = ScheduledTaskProposalPresentation(
        id: "proposal-create-snapshot",
        action: .create,
        sourceConversationID: "proposal-editor-source",
        targetDefinitionID: nil,
        expectedDefinitionRevision: nil,
        targetTitle: nil,
        targetScheduleSummary: nil,
        definitionDraft: ScheduledTaskProposalDefinitionDraft(
            title: "Review open pull requests",
            prompt: "Summarize open pull requests, identify risks, and recommend the next review.",
            recurrence: .weekdays(hour: 9, minute: 0),
            timeZoneIdentifier: "America/Chicago",
            providerID: "codex",
            model: nil,
            effort: "medium",
            permissionMode: "on-request",
            workspaceKind: .privateWorkspace,
            workspaceStrategy: .worktree,
            grantedRoots: ["/tmp/review-inputs"],
            projectPath: nil
        ),
        createdAt: Date(timeIntervalSince1970: 1_800_000_000),
        conflictMessage: nil
    )
    let intervalEditorProposal = ScheduledTaskProposalPresentation(
        id: "proposal-interval-snapshot",
        action: .create,
        sourceConversationID: "proposal-interval-source",
        targetDefinitionID: nil,
        expectedDefinitionRevision: nil,
        targetTitle: nil,
        targetScheduleSummary: nil,
        definitionDraft: ScheduledTaskProposalDefinitionDraft(
            title: "Hello Every Minute",
            prompt: "Say \"Hello\".",
            recurrence: .interval(
                minutes: 1,
                anchor: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            timeZoneIdentifier: "America/Chicago",
            providerID: "claude",
            model: nil,
            effort: "medium",
            permissionMode: "default",
            workspaceKind: .privateWorkspace,
            workspaceStrategy: .worktree,
            grantedRoots: [],
            projectPath: nil
        ),
        createdAt: Date(timeIntervalSince1970: 1_800_000_000),
        conflictMessage: nil
    )
    let coordinator: ScheduledTaskProposalQueueCoordinator
    let viewModel: ScheduledTasksViewModel

    init() throws {
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let notificationCenter = NotificationCenter()
        let mutationService = ScheduledTaskMutationService(
            modelContext: context,
            notificationCenter: notificationCenter
        )
        coordinator = ScheduledTaskProposalQueueCoordinator(
            modelContext: context,
            mutationService: mutationService,
            notificationCenter: notificationCenter,
            runNow: { _ in true }
        )
        viewModel = ScheduledTasksViewModel(
            modelContext: context,
            mutationService: mutationService,
            settingsService: InMemorySettingsService(),
            notificationCenter: notificationCenter,
            runNow: { _ in true }
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
            ScheduledTaskProposal.self,
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

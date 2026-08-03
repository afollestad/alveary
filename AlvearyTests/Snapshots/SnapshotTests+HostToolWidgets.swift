import AppKit
import SwiftData
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testScheduledTaskProposalWidgetPendingAction() throws {
        let fixture = try ScheduledTaskProposalSnapshotFixture()

        assertMacSnapshot(
            appKitRowSnapshot {
                fixture.widgetRow(presentation: fixture.proposal)
            },
            size: CGSize(width: 700, height: 220),
            named: "scheduled_task_proposal_widget_pending_action"
        )
    }

    func testScheduledTaskProposalWidgetPendingActionDark() throws {
        let fixture = try ScheduledTaskProposalSnapshotFixture()

        assertMacSnapshot(
            appKitRowSnapshot {
                fixture.widgetRow(presentation: fixture.proposal)
            },
            size: CGSize(width: 700, height: 220),
            named: "scheduled_task_proposal_widget_pending_action_dark",
            colorScheme: .dark
        )
    }

    func testScheduledTaskProposalWidgetEditorReview() throws {
        let fixture = try ScheduledTaskProposalSnapshotFixture()

        assertMacSnapshot(
            appKitRowSnapshot {
                fixture.widgetRow(presentation: fixture.editorProposal, action: .create)
            },
            size: CGSize(width: 700, height: 200),
            named: "scheduled_task_proposal_widget_editor_review"
        )
    }

    func testScheduledTaskProposalWidgetConfirmed() throws {
        let fixture = try ScheduledTaskProposalSnapshotFixture()

        assertMacSnapshot(
            appKitRowSnapshot {
                fixture.widgetRow(presentation: nil, outcome: .confirmed)
            },
            size: CGSize(width: 700, height: 180),
            named: "scheduled_task_proposal_widget_confirmed"
        )
    }

    /// A lone action spans the card, so it needs its own baseline.
    func testScheduledTaskProposalWidgetConfirmedWithOpenAction() throws {
        let fixture = try ScheduledTaskProposalSnapshotFixture()

        assertMacSnapshot(
            appKitRowSnapshot {
                fixture.widgetRow(presentation: nil, action: .pause, outcome: .confirmed)
            },
            size: CGSize(width: 700, height: 180),
            named: "scheduled_task_proposal_widget_confirmed_open_action"
        )
    }

    func testScheduledTaskProposalWidgetRejected() throws {
        let fixture = try ScheduledTaskProposalSnapshotFixture()

        assertMacSnapshot(
            appKitRowSnapshot {
                fixture.widgetRow(presentation: nil, outcome: .rejected)
            },
            size: CGSize(width: 700, height: 180),
            named: "scheduled_task_proposal_widget_rejected"
        )
    }

    /// The list tool is an ordinary tool row; only its expanded detail is custom.
    func testScheduledTaskListToolExpandedDetail() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitScheduledTaskListDetailView()
                view.configure(
                    rows: [
                        .init(
                            id: "task-1",
                            title: "Review open pull requests",
                            state: .active,
                            scheduleSummary: "Weekdays at 9:00 AM"
                        ),
                        .init(
                            id: "task-2",
                            title: "Nightly dependency audit",
                            state: .paused,
                            scheduleSummary: "Daily at 2:00 AM"
                        )
                    ],
                    typography: TranscriptTypography()
                )
                return view
            },
            size: CGSize(width: 640, height: 140),
            named: "scheduled_task_list_tool_detail"
        )
    }

    func testScheduledTaskProposalWidgetConflict() throws {
        let fixture = try ScheduledTaskProposalSnapshotFixture()

        assertMacSnapshot(
            appKitRowSnapshot {
                fixture.widgetRow(presentation: fixture.conflictedProposal)
            },
            size: CGSize(width: 700, height: 240),
            named: "scheduled_task_proposal_widget_conflict"
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
    let conflictedProposal = ScheduledTaskProposalPresentation(
        id: "proposal-conflict-snapshot",
        action: .delete,
        sourceConversationID: "proposal-source",
        targetDefinitionID: "proposal-target",
        expectedDefinitionRevision: 3,
        targetTitle: "Review open pull requests",
        targetScheduleSummary: "Weekdays at 9:00 AM [America/Chicago]",
        definitionDraft: nil,
        createdAt: Date(timeIntervalSince1970: 1_800_000_000),
        conflictMessage: "This scheduled task changed after the proposal was opened."
    )
    let coordinator: ScheduledTaskProposalQueueCoordinator
    let viewModel: ScheduledTasksViewModel

    func widgetRow(
        presentation: ScheduledTaskProposalPresentation?,
        action: ScheduledTaskProposalAction = .delete,
        outcome: HostToolWidgetOutcome? = nil
    ) -> AppKitTranscriptHostToolWidgetRowView {
        let content = ScheduledTaskProposalWidgetContent(
            action: action,
            proposedTitle: "Review open pull requests",
            recurrence: .weekdays(hour: 9, minute: 0),
            timeZoneIdentifier: "America/Chicago",
            targetDefinitionID: "proposal-target",
            proposalID: presentation?.id ?? "proposal-delete-snapshot",
            message: "Opened a proposal for confirmation.",
            status: .pendingConfirmation
        )
        let entry = HostToolWidgetEntry(
            id: "tool-proposal",
            toolName: HostToolTranscriptCatalog.toolName(ScheduledTaskHostToolCatalog.proposeToolName),
            content: .scheduledTaskProposal(content),
            isComplete: true,
            outcomeKey: presentation?.id ?? "proposal-delete-snapshot",
            outcome: outcome
        )
        let view = AppKitTranscriptHostToolWidgetRowView()
        view.configure(
            .init(
                entry: entry,
                proposalPresentation: presentation,
                isProposalInteractive: presentation != nil,
                bubbleMaxWidth: 640
            )
        )
        return view
    }

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

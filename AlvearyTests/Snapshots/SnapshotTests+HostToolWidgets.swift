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

    /// With nothing scheduled the detail still renders a row, so expanding never reads as broken.
    func testScheduledTaskListToolExpandedDetailWhenEmpty() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitScheduledTaskListDetailView()
                view.configure(rows: [], typography: TranscriptTypography())
                return view
            },
            size: CGSize(width: 640, height: 60),
            named: "scheduled_task_list_tool_detail_empty"
        )
    }

    /// The link card has no body view: the summary, the pull request's title, and the
    /// chevron that says the card opens it are the whole widget.
    func testPullRequestLinkWidget() {
        assertMacSnapshot(
            appKitRowSnapshot { self.pullRequestLinkWidgetRow(action: .link) },
            size: CGSize(width: 700, height: 120),
            named: "pull_request_link_widget"
        )
    }

    func testPullRequestLinkWidgetDark() {
        assertMacSnapshot(
            appKitRowSnapshot { self.pullRequestLinkWidgetRow(action: .link) },
            size: CGSize(width: 700, height: 120),
            named: "pull_request_link_widget_dark",
            colorScheme: .dark
        )
    }

    func testPullRequestUnlinkWidget() {
        assertMacSnapshot(
            appKitRowSnapshot { self.pullRequestLinkWidgetRow(action: .unlink) },
            size: CGSize(width: 700, height: 120),
            named: "pull_request_unlink_widget"
        )
    }

    /// A refused call keeps the card, so the reason has somewhere to render.
    func testPullRequestLinkWidgetFailed() {
        assertMacSnapshot(
            appKitRowSnapshot {
                self.pullRequestLinkWidgetRow(
                    action: .link,
                    status: .failed,
                    message: "GitHub could not be reached."
                )
            },
            size: CGSize(width: 700, height: 120),
            named: "pull_request_link_widget_failed"
        )
    }

    /// A created thread's card carries the workspace it works in on the detail line; the
    /// chevron says the card selects that thread.
    func testThreadCreateWidget() {
        assertMacSnapshot(
            appKitRowSnapshot { self.threadActionWidgetRow(action: .create, projectPath: "/repos/alveary") },
            size: CGSize(width: 700, height: 120),
            named: "thread_create_widget"
        )
    }

    func testThreadCreateWidgetDark() {
        assertMacSnapshot(
            appKitRowSnapshot { self.threadActionWidgetRow(action: .create, projectPath: "/repos/alveary") },
            size: CGSize(width: 700, height: 120),
            named: "thread_create_widget_dark",
            colorScheme: .dark
        )
    }

    /// Placement changes have nothing to add under the summary, so the card is one line.
    func testThreadPinWidget() {
        assertMacSnapshot(
            appKitRowSnapshot { self.threadActionWidgetRow(action: .pin) },
            size: CGSize(width: 700, height: 100),
            named: "thread_pin_widget"
        )
    }

    func testThreadArchiveWidget() {
        assertMacSnapshot(
            appKitRowSnapshot { self.threadActionWidgetRow(action: .archive) },
            size: CGSize(width: 700, height: 100),
            named: "thread_archive_widget"
        )
    }

    private func threadActionWidgetRow(
        action: ThreadActionWidgetContent.Action,
        projectPath: String? = nil,
        status: ThreadActionWidgetContent.Status = .applied
    ) -> AppKitTranscriptHostToolWidgetRowView {
        let entry = HostToolWidgetEntry(
            id: "tool-thread-action",
            toolName: HostToolTranscriptCatalog.toolName(ThreadHostToolCatalog.createThreadToolName),
            content: .threadAction(
                ThreadActionWidgetContent(
                    action: action,
                    threadID: "conv-1",
                    name: "Add caching to the diff viewer",
                    projectPath: projectPath,
                    message: "Done.",
                    status: status
                )
            ),
            isComplete: true
        )
        let view = AppKitTranscriptHostToolWidgetRowView()
        view.configure(.init(entry: entry, bubbleMaxWidth: 640))
        return view
    }

    private func pullRequestLinkWidgetRow(
        action: PullRequestLinkWidgetContent.Action,
        status: PullRequestLinkWidgetContent.Status = .applied,
        message: String = "Linked it."
    ) -> AppKitTranscriptHostToolWidgetRowView {
        let entry = HostToolWidgetEntry(
            id: "tool-pull-request-link",
            toolName: HostToolTranscriptCatalog.toolName(ThreadHostToolCatalog.linkPullRequestToolName),
            content: .pullRequestLink(
                PullRequestLinkWidgetContent(
                    action: action,
                    identifier: PullRequestIdentifier(owner: "acme", repo: "alveary", number: 412),
                    title: "Add caching to the diff viewer",
                    message: message,
                    status: status
                )
            ),
            isComplete: true,
            isError: status == .failed
        )
        let view = AppKitTranscriptHostToolWidgetRowView()
        view.configure(.init(entry: entry, bubbleMaxWidth: 640))
        return view
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
            destination: .newThreadPerRun,
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

import SwiftData
import SwiftUI

@testable import Alveary

/// Seeds the scheduled-task snapshot suite. Lives beside those tests rather than inside them
/// so the suite file stays under the file-length limit.
@MainActor
final class ScheduledTasksSnapshotFixture {
    let container: ModelContainer
    let viewModel: ScheduledTasksViewModel

    /// `includeReusedThreadTask` is separate from `includeTasks` so the reuse schedule cannot
    /// join — and reflow — every populated-screen baseline.
    init(
        includeTasks: Bool = true,
        includeReusedThreadTask: Bool = false,
        pullRequestsEnabled: Bool = true
    ) throws {
        container = try Self.makeContainer()
        let context = ModelContext(container)
        let notificationCenter = NotificationCenter()
        if includeTasks {
            try Self.insertFixtures(into: context)
        }
        if includeReusedThreadTask {
            context.insert(Self.reusedThreadTask())
            try context.save()
        }
        let mutationService = ScheduledTaskMutationService(
            modelContext: context,
            notificationCenter: notificationCenter
        )
        // Gates which suggestion leads the empty state's roster.
        let settingsService = InMemorySettingsService()
        settingsService.update { $0.pullRequestsEnabled = pullRequestsEnabled }
        viewModel = ScheduledTasksViewModel(
            modelContext: context,
            mutationService: mutationService,
            settingsService: settingsService,
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

    /// A reuse schedule past its first run: the linked thread carries a workspace root and a sole
    /// main conversation, which is what `isHealthyReusedScheduledTaskTarget` needs before the card
    /// and editor will name it.
    private static func reusedThreadTask() -> ScheduledTask {
        let thread = AgentThread(name: "Morning triage", mode: .task)
        thread.taskWorkspaceDescriptor = TaskWorkspaceDescriptor(
            primaryRoot: "/tmp/alveary-snapshot-reuse",
            ownershipStrategy: .projectLocal
        )
        thread.conversations = [Conversation(id: "reused-snapshot-main", provider: "claude", thread: thread)]
        let task = ScheduledTask(
            id: "reused-snapshot",
            title: "Triage overnight failures",
            prompt: "Summarize overnight failures and propose the first fix.",
            destination: .reusedThread,
            state: .active,
            recurrence: .daily(hour: 8, minute: 0),
            timeZoneIdentifier: "America/Chicago",
            providerID: "claude",
            workspaceKind: .privateWorkspace,
            workspaceStrategy: .worktree,
            nextOccurrenceAt: Date(timeIntervalSince1970: 1_800_028_800),
            modifiedAt: Date(timeIntervalSince1970: 400)
        )
        task.reusedThread = thread
        return task
    }

    private static func activeTask(project: Project) -> ScheduledTask {
        ScheduledTask(
            id: "active-snapshot",
            title: "Review open pull requests",
            prompt: "Summarize open pull requests, identify risks, and recommend the next review.",
            destination: .newThreadPerRun,
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
            destination: .newThreadPerRun,
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
            destination: .newThreadPerRun,
            state: .completed,
            recurrence: .once(Date(timeIntervalSince1970: 1_799_900_000)),
            timeZoneIdentifier: "UTC",
            providerID: "codex",
            workspaceKind: .privateWorkspace,
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
    }
}

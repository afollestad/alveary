#if DEBUG
import Foundation
import SwiftData

/// Scheduled task definitions plus the two inert runs that give the review threads their sidebar
/// provenance indicator.
///
/// Every active definition gets a strictly future `nextOccurrenceAt`, and the runs are terminal
/// with no prepared-workspace or pending-cleanup metadata — that combination is what keeps
/// orphan-cleanup and marker-verification paths from engaging against fake paths.
@MainActor
extension DemoDataSeeder {
    static let timeZoneIdentifier = "America/Chicago"

    /// The one paused row that carries a banner. `ScheduledTaskPreflightValidationError`'s
    /// `missingProjectWorkspace` case produces this sentence when a project-scoped schedule's
    /// workspace has gone missing, which is true of every demo project path — so the row states
    /// something demo mode has really made true.
    static let preflightPauseReason = "The scheduled task Project workspace is missing."

    static func insertScheduledTasks(
        projects: DemoProjects,
        reviewThreads: DemoReviewThreads,
        into context: ModelContext
    ) {
        // The hero task: its prompt describes the fan-out, and threads 9 and 10 are its output.
        let reviewFanOut = ScheduledTask(
            id: DemoData.reviewFanOutTaskID,
            title: "Review PRs and propose reviews",
            prompt: DemoData.reviewFanOutPrompt,
            state: .active,
            recurrence: .weekdays(hour: 9, minute: 0),
            timeZoneIdentifier: timeZoneIdentifier,
            providerID: "claude",
            workspaceKind: .privateWorkspace,
            nextOccurrenceAt: DemoData.minutesFromNow(60 * 14),
            createdAt: DemoData.daysAgo(24),
            modifiedAt: DemoData.daysAgo(9)
        )
        context.insert(reviewFanOut)
        insertProjectScopedTasks(projects: projects, into: context)
        insertProjectlessTasks(into: context)
        insertReviewRuns(definition: reviewFanOut, reviewThreads: reviewThreads, into: context)
    }

    /// The three definitions attached to a project — two on Waypoint, one on Ledger. Hummingbird
    /// deliberately has threads but no schedules, and docs-site has neither.
    private static func insertProjectScopedTasks(projects: DemoProjects, into context: ModelContext) {
        context.insert(makeChangelogTask(project: projects.waypoint))
        context.insert(makeDependencyAuditTask(project: projects.ledger))
        context.insert(makeReleaseNotesTask(project: projects.waypoint))
    }

    private static func makeChangelogTask(project: Project) -> ScheduledTask {
        ScheduledTask(
            id: "demo-task-changelog",
            title: "Monthly changelog roundup",
            prompt: """
                Compile a customer-facing changelog from everything merged since the last release. \
                Group by theme, skip internal refactors, and link each entry to its pull request.
                """,
            state: .paused,
            recurrence: .monthly(day: 1, hour: 8, minute: 0),
            timeZoneIdentifier: timeZoneIdentifier,
            providerID: "claude",
            workspaceKind: .project,
            project: project,
            // No `pauseReason`: pausing by hand clears it, so a user-paused row carries no banner.
            nextOccurrenceAt: DemoData.minutesFromNow(60 * 24 * 11),
            createdAt: DemoData.daysAgo(61),
            modifiedAt: DemoData.daysAgo(4)
        )
    }

    private static func makeDependencyAuditTask(project: Project) -> ScheduledTask {
        ScheduledTask(
            id: "demo-task-dependency-audit",
            title: "Nightly dependency audit",
            prompt: """
                Check every package for outdated or vulnerable versions. If anything has a known \
                advisory, open a thread with the upgrade path and the blast radius.
                """,
            state: .active,
            recurrence: .daily(hour: 2, minute: 30),
            timeZoneIdentifier: timeZoneIdentifier,
            providerID: "claude",
            workspaceKind: .project,
            workspaceStrategy: .worktree,
            project: project,
            nextOccurrenceAt: DemoData.minutesFromNow(60 * 7),
            createdAt: DemoData.daysAgo(38),
            modifiedAt: DemoData.daysAgo(38)
        )
    }

    private static func makeReleaseNotesTask(project: Project) -> ScheduledTask {
        ScheduledTask(
            id: "demo-task-release-notes",
            title: "Refresh release notes",
            prompt: """
                Draft release notes from the pull requests merged this week. Lead with what users \
                can see, and keep each entry to one sentence.
                """,
            state: .paused,
            // Calendar weekdays: 1 is Sunday, so 7 is Saturday.
            recurrence: .weekly(weekday: 7, hour: 15, minute: 30),
            timeZoneIdentifier: timeZoneIdentifier,
            providerID: "claude",
            workspaceKind: .project,
            project: project,
            nextOccurrenceAt: DemoData.minutesFromNow(60 * 24 * 3),
            // Verbatim from `ScheduledTaskPreflightValidationError.missingProjectWorkspace`, and
            // written to both fields the way `pauseInvalidDefinition` writes them. Only the engine
            // and `pauseForProjectDeletion` ever fill these, so a hand-written sentence here would
            // put prose in a slot that only carries machine text.
            pauseReason: preflightPauseReason,
            lastError: preflightPauseReason,
            createdAt: DemoData.daysAgo(52),
            modifiedAt: DemoData.daysAgo(7)
        )
    }

    /// The two project-less definitions, both running in a private workspace.
    private static func insertProjectlessTasks(into context: ModelContext) {
        context.insert(
            ScheduledTask(
                id: "demo-task-screenshots",
                title: "Sync docs screenshots",
                prompt: """
                    Regenerate the marketing screenshots whenever a UI change lands, and tell me which \
                    ones actually changed so I do not re-upload the whole set.
                    """,
                state: .active,
                recurrence: .interval(minutes: 240, anchor: DemoData.hoursAgo(2)),
                timeZoneIdentifier: timeZoneIdentifier,
                providerID: "codex",
                workspaceKind: .privateWorkspace,
                nextOccurrenceAt: DemoData.minutesFromNow(120),
                createdAt: DemoData.daysAgo(15),
                modifiedAt: DemoData.daysAgo(15)
            )
        )

        context.insert(
            ScheduledTask(
                id: "demo-task-launch-checklist",
                title: "Prepare launch checklist",
                prompt: "Assemble the v1.0 launch checklist and flag anything still unowned.",
                state: .completed,
                recurrence: .once(DemoData.daysAgo(3)),
                timeZoneIdentifier: timeZoneIdentifier,
                providerID: "codex",
                workspaceKind: .privateWorkspace,
                createdAt: DemoData.daysAgo(19),
                modifiedAt: DemoData.daysAgo(3)
            )
        )
    }

    private static func insertReviewRuns(
        definition: ScheduledTask,
        reviewThreads: DemoReviewThreads,
        into context: ModelContext
    ) {
        context.insert(
            makeInertRun(
                suffix: "waypoint-57",
                definition: definition,
                thread: reviewThreads.waypoint,
                finishedAt: DemoData.hoursAgo(6)
            )
        )
        context.insert(
            makeInertRun(
                suffix: "ledger-128",
                definition: definition,
                thread: reviewThreads.ledger,
                finishedAt: DemoData.hoursAgo(6).addingTimeInterval(-4 * 60)
            )
        )
    }

    /// Terminal, recovered, and workspace-less: every `preparedWorkspace*`,
    /// `pendingWorktreeCleanup*`, and provenance field stays nil so nothing tries to verify an
    /// ownership marker or remove a worktree at a fake path.
    private static func makeInertRun(
        suffix: String,
        definition: ScheduledTask,
        thread: AgentThread,
        finishedAt: Date
    ) -> ScheduledTaskRun {
        let occurrenceAt = finishedAt.addingTimeInterval(-15 * 60)
        return ScheduledTaskRun(
            id: "demo-run-\(suffix)",
            occurrenceID: "demo-occurrence-\(suffix)",
            triggerID: "demo-trigger-\(suffix)",
            definitionID: definition.id,
            definitionRevision: definition.revision,
            occurrenceAt: occurrenceAt,
            triggeredAt: occurrenceAt,
            triggerKind: .scheduled,
            status: .success,
            titleSnapshot: definition.title,
            promptSnapshot: definition.prompt,
            timeZoneIdentifierSnapshot: definition.timeZoneIdentifier,
            providerIDSnapshot: definition.providerID,
            effortSnapshot: definition.effort,
            permissionModeSnapshot: definition.permissionMode,
            workspaceKindSnapshot: .privateWorkspace,
            workspaceStrategySnapshot: definition.workspaceStrategy,
            claimedAt: occurrenceAt,
            startedAt: occurrenceAt,
            finishedAt: finishedAt,
            requiresFinalizationRecovery: false,
            scheduledTask: definition,
            thread: thread,
            targetThread: thread
        )
    }
}
#endif

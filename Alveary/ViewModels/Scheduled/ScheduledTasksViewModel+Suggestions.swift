import Foundation

/// The Scheduled empty state's starting points: the roster the cards render, and the draft
/// a picked card seeds the create pane with.
extension ScheduledTasksViewModel {
    /// Three suggestions, always. The pull-request slot is gated on the same
    /// `AppSettings.pullRequestsEnabled` that hides the sidebar row, because the prompt
    /// leans on host tools that refuse while the integration is off; the dependency check
    /// takes that slot instead so the empty state does not change shape with a setting.
    var firstTaskSuggestions: [ScheduledTaskSuggestion] {
        let leading = settingsService.current.pullRequestsEnabled
            ? Self.pullRequestReviewSuggestion
            : Self.dependencyCheckSuggestion
        return [leading, Self.projectDigestSuggestion, Self.agentsRefreshSuggestion]
    }

    /// A create draft carrying the suggestion's task and schedule. Workspace and agent stay
    /// on `makeNewDraft()`'s defaults on purpose: the pane opens for review, and guessing
    /// one of several registered Projects would be a choice the user never made.
    func makeSuggestionDraft(_ suggestion: ScheduledTaskSuggestion) -> ScheduledTaskEditorDraft {
        var draft = makeNewDraft()
        let recurrence = Self.recurrence(
            for: suggestion.schedule,
            intervalAnchor: startOfMinute(now())
        )
        // The same decomposition proposals use, rather than assigning the fields this
        // recurrence happens to need: a case gaining a field cannot leave one stale here.
        let fields = ProposalDraftRecurrenceFields(
            recurrence: recurrence,
            fallbackOnceOccurrence: draft.onceOccurrenceAt,
            fallbackIntervalAnchor: draft.intervalAnchorAt
        )
        draft.title = suggestion.title
        draft.prompt = suggestion.prompt
        draft.recurrenceKind = recurrence.kind
        draft.onceOccurrenceAt = fields.onceOccurrenceAt
        draft.intervalAnchorAt = fields.intervalAnchorAt
        draft.intervalMinutes = fields.intervalMinutes
        draft.wallClockHour = fields.wallClockHour
        draft.wallClockMinute = fields.wallClockMinute
        draft.selectedWeekdays = fields.selectedWeekdays
        draft.weeklyWeekday = fields.weeklyWeekday
        draft.monthlyDay = fields.monthlyDay
        return draft
    }
}

private extension ScheduledTasksViewModel {
    static func recurrence(
        for schedule: ScheduledTaskSuggestion.Schedule,
        intervalAnchor: Date
    ) -> ScheduledTaskRecurrence {
        switch schedule {
        case .everyMinutes(let minutes):
            .interval(minutes: minutes, anchor: intervalAnchor)
        case let .daily(hour, minute):
            .daily(hour: hour, minute: minute)
        case let .weekdays(hour, minute):
            .weekdays(hour: hour, minute: minute)
        case let .weekly(weekday, hour, minute):
            .weekly(weekday: weekday, hour: hour, minute: minute)
        }
    }

    /// The spawned thread's name is this prompt's only ledger. A `newThread` schedule keeps no
    /// state between runs, so skipping pull requests that already have a thread is what advances
    /// the batch past the first twenty — GitHub drops one from `review-requested:@me` only once a
    /// review is *submitted*, which a proposal awaiting the user's card has not done. The template
    /// matches `PullRequestAgenticThreadService`'s `"Review \(displayKey)"` so a review started by
    /// hand from the pull request pane is skipped too; rewording either one alone breaks the skip.
    /// `link_pr` is named outright because `automaticallyLinkPullRequests` may be off, and the pane's
    /// own agentic review links regardless of it — this fan-out should not be the one route that
    /// does not. The nested prompt stays last so nothing trailing it reads as part of what the
    /// spawned thread was handed.
    static let pullRequestReviewSuggestion = ScheduledTaskSuggestion(
        id: "pull-request-review",
        icon: .octicon(.pullRequest16),
        title: "Review pull requests",
        scheduleCaption: "Every 6 hours",
        prompt: "Fetch PRs that need my review, skipping any that already have a review thread — "
            + "check my existing thread names first, and keep paging until you have 20 that do not. "
            + "Then create a new thread for each one, named like \"Review owner/repo#123\", and use the "
            + "link_pr tool to link that PR to the thread you just created. Give each of those threads "
            + "this prompt, where [PR URL] is the actual URL: Perform an agentic review on [PR URL].",
        schedule: .everyMinutes(360)
    )

    static let dependencyCheckSuggestion = ScheduledTaskSuggestion(
        id: "dependency-check",
        icon: .system("shippingbox"),
        title: "Nightly dependency check",
        scheduleCaption: "Daily at 10:00 PM",
        prompt: "Check my projects for outdated dependencies and known vulnerabilities, "
            + "then propose the upgrades worth taking.",
        schedule: .daily(hour: 22, minute: 0)
    )

    static let projectDigestSuggestion = ScheduledTaskSuggestion(
        id: "project-digest",
        icon: .system("list.bullet.rectangle"),
        title: "Daily project digest",
        scheduleCaption: "Weekdays at 9:00 AM",
        prompt: "Summarize what changed across my projects since yesterday, what work is "
            + "still in flight, and what needs my attention today.",
        schedule: .weekdays(hour: 9, minute: 0)
    )

    /// Calendar weekdays run 1 = Sunday, so Monday is 2 — matching
    /// `ScheduledTaskRecurrence.standardWeekdays`.
    static let agentsRefreshSuggestion = ScheduledTaskSuggestion(
        id: "agents-refresh",
        icon: .system("doc.text"),
        title: "Weekly AGENTS.md refresh",
        scheduleCaption: "Mondays at 9:00 AM",
        prompt: "Review the past week of commits and update the AGENTS.md files wherever "
            + "they have drifted from the code.",
        schedule: .weekly(weekday: 2, hour: 9, minute: 0)
    )
}

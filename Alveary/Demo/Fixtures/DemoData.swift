#if DEBUG
import Foundation

/// Stable identifiers, paths, and clock helpers shared by every demo fixture and the seeder.
///
/// The demo store is wiped and reseeded on each launch, so timestamps are expressed relative to
/// one captured launch instant: relative labels ("4h ago") then read correctly in a screenshot
/// taken minutes later.
enum DemoData {
    static let launchedAt = Date()

    // MARK: Projects

    static let waypointPath = "/Users/demo/Developer/waypoint"
    static let ledgerPath = "/Users/demo/Developer/ledger"
    static let hummingbirdPath = "/Users/demo/Developer/hummingbird"
    static let docsSitePath = "/Users/demo/Developer/docs-site"

    /// The flagship thread's worktree. `DemoGitService` keys its richest canned workspace on this
    /// path, and `AgentThread.primaryWorkingDirectory` resolves a worktree ahead of its project.
    static let tripSharingWorktreePath = "/Users/demo/Developer/waypoint-worktrees/trip-sharing"
    static let tripSharingBranch = "alveary/trip-sharing"

    // MARK: Task workspaces

    static let weeklyPullRequestsWorkspace = "/Users/demo/Workspaces/summarize-weekly-prs"
    static let crashTriageWorkspace = "/Users/demo/Workspaces/triage-crash-reports"
    static let waypointReviewWorkspace = "/Users/demo/Workspaces/review-waypoint-57"
    static let ledgerReviewWorkspace = "/Users/demo/Workspaces/review-ledger-128"

    // MARK: Conversations

    static let tripSharingConversation = "demo-trip-sharing-main"
    static let tripSharingSideConversation = "demo-trip-sharing-side"
    static let flakyMapTestsConversation = "demo-flaky-map-tests"
    static let onboardingConversation = "demo-onboarding-refactor"
    static let structuredLoggingConversation = "demo-structured-logging"
    static let rateLimitConversation = "demo-rate-limit-middleware"
    static let emptyStatesConversation = "demo-empty-states"
    static let weeklyPullRequestsConversation = "demo-weekly-pull-requests"
    static let crashTriageConversation = "demo-crash-triage"
    static let archivedConversation = "demo-archived-spike"
    static let waypointReviewConversation = "demo-review-waypoint-57"
    static let ledgerReviewConversation = "demo-review-ledger-128"

    // MARK: Scheduled tasks

    static let reviewFanOutTaskID = "demo-task-review-fan-out"

    /// The hero scheduled task's prompt, shown verbatim on the Scheduled screen and echoed by the
    /// two review threads it fans out to.
    static let reviewFanOutPrompt = """
        List PRs that I need to review, and launch new tasks for each one to review their diff. \
        For each diff review, generate comments and propose the review to me.
        """

    // MARK: Clock helpers

    static func minutesAgo(_ minutes: Double) -> Date {
        launchedAt.addingTimeInterval(-minutes * 60)
    }

    static func hoursAgo(_ hours: Double) -> Date {
        minutesAgo(hours * 60)
    }

    static func daysAgo(_ days: Double) -> Date {
        hoursAgo(days * 24)
    }

    static func minutesFromNow(_ minutes: Double) -> Date {
        launchedAt.addingTimeInterval(minutes * 60)
    }
}
#endif

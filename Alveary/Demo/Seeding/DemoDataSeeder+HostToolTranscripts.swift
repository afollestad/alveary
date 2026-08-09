#if DEBUG
import Foundation
import SwiftData

/// The `alveary_host` widget transcripts: the pull-request list, link, and thread-action cards,
/// both prompt states, a scheduled-task proposal, and the two review proposals the hero scheduled
/// task fans out to.
///
/// Every payload here is shaped the way its widget parser reads it, which is why the tool names
/// use the qualified `mcp__alveary_host__*` form and the review event value is lowercase
/// snake_case — the parser accepts `approve` / `request_changes` / `comment` and nothing else.
@MainActor
extension DemoDataSeeder {
    static func seedWeeklyPullRequestsTranscript(_ conversation: Conversation, into context: ModelContext) {
        let builder = DemoTranscriptBuilder(conversation: conversation)
        builder.user("What's waiting on me across all my repos this week?")
        builder.tool(
            id: "demo-h1",
            name: hostTool(PullRequestHostToolCatalog.listToolName),
            input: #"{"filter":"all"}"#,
            output: pullRequestListOutput
        )
        builder.assistant(
            """
            Six open threads of work. Two are yours, two are waiting on your review, and the other \
            two have already landed. Linking the one you asked about last week so it stays with this task.
            """
        )
        builder.tool(
            id: "demo-h2",
            name: hostTool(ThreadHostToolCatalog.linkPullRequestToolName),
            input: #"{"url":"https://github.com/demo/waypoint/pull/57"}"#,
            output: linkPullRequestOutput
        )
        builder.assistant("And spinning up a thread for the tile-caching review so it does not block this summary.")
        builder.tool(
            id: "demo-h3",
            name: hostTool(ThreadHostToolCatalog.createThreadToolName),
            input: #"{"name":"Review demo/waypoint#57 — Cache tile downloads","mode":"task"}"#,
            output: createThreadOutput
        )
        builder.tokens(input: 29_400, output: 1_620, cacheRead: 11_200, costUsd: 0.24, model: "claude-opus-5")
        builder.commit(into: context, endingAt: DemoData.minutesAgo(48))
    }

    /// Both prompt states plus a scheduled-task proposal. The unanswered question stays at the
    /// tail, and this conversation deliberately holds no permission approvals — an unanswered
    /// question disables approval controls for the whole conversation.
    static func seedCrashTriageTranscript(_ conversation: Conversation, into context: ModelContext) {
        let builder = DemoTranscriptBuilder(conversation: conversation)
        builder.user("Group this week's crash reports and tell me which one to fix first.")
        builder.question(id: "demo-q1", input: crashGroupingQuestionInput, answeredSummary: "Group by stack signature")
        builder.assistant(
            """
            Grouped by stack signature: 412 reports collapse into 9 signatures. The top one is a \
            main-thread deadlock in the tile cache, 61% of the volume and all on macOS 26.1.
            """
        )
        builder.tool(
            id: "demo-q2",
            name: hostTool(ScheduledTaskHostToolCatalog.proposeToolName),
            input: crashDigestProposalInput,
            output: crashDigestProposalOutput
        )
        builder.hostToolOutcome(
            toolName: hostTool(ScheduledTaskHostToolCatalog.proposeToolName),
            key: crashDigestProposalID,
            payload: HostToolWidgetOutcomeMarker.content(for: .confirmed, title: "Weekly crash digest")
        )
        builder.assistant("Scheduled. One more decision before I open the fix.")
        builder.question(id: "demo-q3", input: crashFixQuestionInput)
        builder.commit(into: context, endingAt: DemoData.hoursAgo(20))
    }

    /// One of the two threads the hero scheduled task fans out to. Ends in the review-proposal
    /// card the task's prompt describes producing.
    static func seedReviewProposalTranscript(
        _ conversation: Conversation,
        proposal: DemoReviewProposal,
        endingAt: Date,
        into context: ModelContext
    ) {
        let url = pullRequestURL(proposal.pullRequest)
        let builder = DemoTranscriptBuilder(conversation: conversation)
        builder.user("Review \(proposal.pullRequest.displayKey) and propose the review to me when you're done.")
        builder.tool(
            id: "\(proposal.proposalID)-instructions",
            name: hostTool(PullRequestHostToolCatalog.reviewInstructionsToolName),
            input: #"{"url":"\#(url)"}"#,
            output: reviewInstructionsOutput
        )
        builder.tool(
            id: "\(proposal.proposalID)-diff",
            name: hostTool(PullRequestHostToolCatalog.diffToolName),
            input: #"{"url":"\#(url)"}"#,
            output: diffShortstat(for: proposal.pullRequest)
        )
        builder.assistant(proposal.summary)
        builder.tool(
            id: "\(proposal.proposalID)-propose",
            name: hostTool(PullRequestHostToolCatalog.proposeReviewToolName),
            input: proposeReviewInput(proposal),
            output: proposeReviewOutput(proposal)
        )
        builder.tokens(input: 46_200, output: 2_480, cacheRead: 19_800, costUsd: 0.36, model: "claude-opus-5")
        builder.commit(into: context, endingAt: endingAt)
    }

    static func hostTool(_ name: String) -> String {
        HostToolTranscriptCatalog.toolName(name)
    }

    static func pullRequestURL(_ id: PullRequestIdentifier) -> String {
        "https://github.com/\(id.nameWithOwner)/pull/\(id.number)"
    }

    /// `git diff --shortstat` phrasing derived from the pull request's served diff, so the
    /// transcript's fetch-diff row cannot drift from what the pane renders for the same URL.
    static func diffShortstat(for id: PullRequestIdentifier) -> String {
        let files = DiffParser.parse(DemoPullRequestFixtures.diff(for: id) ?? "")
        let additions = files.reduce(0) { $0 + $1.linesAdded }
        let deletions = files.reduce(0) { $0 + $1.linesDeleted }
        func count(_ value: Int, _ noun: String) -> String {
            "\(value) \(noun)\(value == 1 ? "" : "s")"
        }
        return "\(count(files.count, "file")) changed, "
            + "\(count(additions, "insertion"))(+), \(count(deletions, "deletion"))(-)"
    }
}

private extension DemoDataSeeder {
    static let crashDigestProposalID = "demo-proposal-crash-digest"

    static func proposeReviewInput(_ proposal: DemoReviewProposal) -> String {
        // `event` values are lowercase snake_case; `url` and `event` are the required keys, and
        // the `comments` array is what gives the card its comment count.
        #"""
        {"url":"\#(pullRequestURL(proposal.pullRequest))","event":"request_changes",\#
        "body":"\#(jsonEscaped(proposal.summary))","comments":\#(proposal.comments)}
        """#
    }

    static func proposeReviewOutput(_ proposal: DemoReviewProposal) -> String {
        let pullRequest = proposal.pullRequest
        return #"""
        {"status":"pending_confirmation","proposal_id":"\#(proposal.proposalID)",\#
        "repository":"\#(pullRequest.nameWithOwner)","number":\#(pullRequest.number),\#
        "pending_comment_count":\#(proposal.commentCount),\#
        "message":"Proposed a review of \#(pullRequest.displayKey). Waiting for confirmation."}
        """#
    }

    /// Collapses newlines and quotes so a multi-paragraph body survives inside a JSON literal.
    static func jsonEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    static let pullRequestListOutput = #"""
        {"filter":"all","total_count":6,"warnings":[],"pull_requests":[\#
        {"repository":"demo/waypoint","number":61,"title":"Rework the onboarding walkthrough","status":"open"},\#
        {"repository":"demo/hummingbird","number":74,"title":"Search results empty state","status":"open"},\#
        {"repository":"demo/ledger","number":128,"title":"Idempotent webhook retries","status":"draft"},\#
        {"repository":"demo/waypoint","number":57,"title":"Cache tile downloads for offline maps","status":"open"},\#
        {"repository":"demo/ledger","number":96,"title":"Rate limit middleware for the public API","status":"merged"},\#
        {"repository":"demo/hummingbird","number":41,"title":"Try a bottom sheet for filters","status":"closed"}]}
        """#

    static let linkPullRequestOutput = #"""
        {"status":"linked","pull_request":{"repository":"demo/waypoint","number":57,\#
        "title":"Cache tile downloads for offline maps","status":"open"},\#
        "message":"Linked demo/waypoint#57 to this thread."}
        """#

    static let createThreadOutput = #"""
        {"thread_id":"demo-thread-review-waypoint-57","name":"Review demo/waypoint#57 — Cache tile downloads",\#
        "message":"Created the thread \"Review demo/waypoint#57 — Cache tile downloads\" (id: demo-thread-review-waypoint-57)."}
        """#

    static let reviewInstructionsOutput = #"""
        {"instructions":"Read the whole diff before commenting. Anchor every remark to a line that \#
        actually changed. Prefer one substantive comment over three stylistic ones, and say plainly \#
        when the change looks right."}
        """#

    static let crashGroupingQuestionInput = #"""
        {"questions":[{"question":"How should I group this week's crash reports?",\#
        "header":"Grouping","multiSelect":false,"options":[\#
        {"label":"Group by stack signature","description":"Collapses reports that share a top frame."},\#
        {"label":"Group by release","description":"Shows which build regressed."},\#
        {"label":"Group by device class","description":"Separates Apple silicon from Intel."}]}]}
        """#

    static let crashFixQuestionInput = #"""
        {"questions":[{"question":"The deadlock fix can ship two ways. Which do you want?",\#
        "header":"Approach","multiSelect":false,"options":[\#
        {"label":"Move the cache read off the main thread","description":"Smaller change, keeps the current API."},\#
        {"label":"Make TileCache an actor","description":"Removes the class of bug, touches 11 call sites."}]}]}
        """#

    static let crashDigestProposalInput = #"""
        {"action":"create","title":"Weekly crash digest",\#
        "prompt":"Group the week's crash reports by stack signature and summarize the top three.",\#
        "schedule":{"kind":"weekly","weekday":2,"hour":9,"minute":0,"time_zone":"America/Chicago"}}
        """#

    static let crashDigestProposalOutput = #"""
        {"status":"pending_confirmation","proposal_id":"\#(crashDigestProposalID)",\#
        "title":"Weekly crash digest","message":"Proposed a weekly crash digest. Waiting for confirmation."}
        """#
}
#endif

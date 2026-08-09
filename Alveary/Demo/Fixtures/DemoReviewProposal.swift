#if DEBUG
import Foundation

/// One spawned review thread and the proposal card it ends on — the visible output of the hero
/// scheduled task's fan-out. Grouped into a value type so the seeder and transcript builders take
/// one parameter instead of eight.
struct DemoReviewProposal: Sendable {
    let pullRequest: PullRequestIdentifier
    let threadName: String
    let workspace: String
    let conversationID: String
    let proposalID: String
    let summary: String
    /// The `comments` array verbatim, as the request carries it: its length is what gives the
    /// card its comment count. Each entry's `path` and `line` must name a line the pull request's
    /// served diff draws, or the staged comment renders on the card and nowhere in the Changes tab.
    let comments: String
    let commentCount: Int
}

extension DemoReviewProposal {
    static let waypointTileCaching = DemoReviewProposal(
        pullRequest: DemoPullRequestFixtures.tileCaching,
        threadName: "Review demo/waypoint#57 — Cache tile downloads",
        workspace: DemoData.waypointReviewWorkspace,
        conversationID: DemoData.waypointReviewConversation,
        proposalID: "demo-proposal-waypoint-57",
        summary: """
            The cache itself looks right, and the in-flight coalescing is the part I would have \
            asked for. Two things before this lands: the eviction pass runs on the actor, so a \
            large sweep blocks every tile read behind it, and the disk read is not bounded, so a \
            truncated file decodes to a blank tile rather than a miss.
            """,
        // Raw string, so its line continuations are `\#` — a bare `\` would land a literal
        // backslash in the JSON and the card would fail to count the comments.
        comments: #"""
            [{"path":"Sources/Waypoint/Map/TileCache.swift","line":21,"side":"RIGHT",\#
            "body":"A truncated file decodes to a blank tile here rather than a miss. Worth validating the byte count first."},\#
            {"path":"Sources/Waypoint/Map/TileCache.swift","line":45,"side":"RIGHT",\#
            "body":"The eviction sweep runs on the actor, so a large pass blocks every tile read behind it."}]
            """#,
        commentCount: 2
    )

    static let ledgerWebhookRetries = DemoReviewProposal(
        pullRequest: DemoPullRequestFixtures.webhookRetries,
        threadName: "Review demo/ledger#128 — Idempotent webhook retries",
        workspace: DemoData.ledgerReviewWorkspace,
        conversationID: DemoData.ledgerReviewConversation,
        proposalID: "demo-proposal-ledger-128",
        summary: """
            The retry key is derived from the whole payload, which includes the timestamp — so a \
            webhook replayed with a fresh timestamp gets a new key and runs twice. That is exactly \
            the case this change is meant to close. The backoff and the dead-letter path both read well.
            """,
        comments: #"""
            [{"path":"Sources/Ledger/Webhooks/RetryKey.swift","line":18,"side":"RIGHT",\#
            "body":"Deriving the key from the whole payload includes the timestamp, so a replay gets a fresh key."},\#
            {"path":"Sources/Ledger/Webhooks/RetryPolicy.swift","line":52,"side":"RIGHT",\#
            "body":"Jitter is applied after the cap, so the last attempt can exceed the documented ceiling."},\#
            {"path":"Tests/LedgerTests/RetryPolicyTests.swift","line":9,"side":"RIGHT",\#
            "body":"Worth a case for the replayed-with-new-timestamp path — that is the regression this closes."}]
            """#,
        commentCount: 3
    )
}
#endif

#if DEBUG
import Foundation

// The conversations on other people's pull requests — the list screen's Reviewing tab, split into
// the two waiting on the viewer and the one they already reviewed.
// `DemoPullRequestFixtures+Conversations.swift` owns the shape and the rules these follow.
extension DemoPullRequestFixtures {
    /// The viewer's turn: a draft pull request waiting on them, with one unsubmitted comment of
    /// their own already written — the orange "Pending" pill and the footer's comment count.
    static let webhookRetriesConversation = DemoPullRequestConversation(
        bodyMarkdown: """
            ## Problem

            A webhook redelivered by the provider runs its handler twice. We de-duplicate on the
            delivery id, but the provider mints a new one on every replay.

            ## Approach

            Derive a `RetryKey` from the event id plus the payload body, and hold it for the
            provider's full replay window. Backoff is capped at the documented ceiling.

            Still a draft — the replayed-with-a-new-timestamp case is not covered yet.
            """,
        createdAt: DemoData.hoursAgo(72),
        changedFiles: 3,
        checks: [
            .demo("build", .passing),
            .demo("integration-tests", .pending)
        ],
        reviewers: [.demo(viewerLogin, .requested)],
        comments: [
            .demo(
                "marcus",
                """
                Back to draft — the key still folds in the timestamp header, which is exactly the
                thing that changes on a replay. Reviewing the shape is still useful though.
                """,
                at: DemoData.hoursAgo(11),
                id: 4_430
            ),
            .demo(
                viewerLogin,
                "Is the replay window the provider's 72 hours, or ours? The two are documented differently.",
                at: DemoData.hoursAgo(10.5),
                id: 4_431
            )
        ],
        reviewThreads: [
            // Unsubmitted: authored by the viewer and belonging to `pendingReviewNodeID` below.
            .demo(
                "Sources/Ledger/Webhooks/RetryPolicy.swift",
                line: 52,
                id: 81,
                excerpt: """
                    private func jitter(upTo limit: Duration) -> Duration {
                        .seconds(Double.random(in: 0...limit.seconds))
                    """,
                comments: [
                    .demoPending(
                        """
                        Jitter is added after the cap, so the last attempt can land past the
                        ceiling this change is meant to enforce.
                        """,
                        at: DemoData.hoursAgo(9.2),
                        id: 4_432
                    )
                ]
            )
        ],
        timelineEvents: [
            .demo(.commit, by: "marcus", at: DemoData.hoursAgo(71), detail: "c0ff33a Derive a retry key from the delivery"),
            .demo(.convertToDraft, by: "marcus", at: DemoData.hoursAgo(12)),
            .demo(.reviewRequested, by: "marcus", at: DemoData.hoursAgo(10), detail: viewerLogin),
            .demo(.commit, by: "marcus", at: DemoData.hoursAgo(9.5), detail: "9ab12de Bound the backoff at the documented ceiling")
        ],
        pendingReviewNodeID: "demo-review-draft-128"
    )

    /// The pull request the hero scheduled task's spawned thread reviews, so its Overview and that
    /// thread's proposal card describe the same code.
    static let tileCachingConversation = DemoPullRequestConversation(
        bodyMarkdown: """
            Tiles are re-downloaded every time the map returns to a region, which is most of what
            offline mode has to avoid.

            This adds a disk-backed `TileCache`, coalesces in-flight downloads so a pan does not
            queue the same tile twice, and evicts by age on launch.
            """,
        createdAt: DemoData.hoursAgo(96),
        changedFiles: 1,
        checks: [
            .demo("build (macOS)", .passing),
            .demo("tile-cache-benchmarks", .passing, url: "https://github.com/demo/waypoint/actions/runs/8790")
        ],
        reviewers: [
            .demo(viewerLogin, .requested),
            .demo("marcus", .commented, canReRequest: true)
        ],
        comments: [
            .demo(
                "priya",
                "Benchmarks are in the actions run: a warm pan goes from 240 requests to 6.",
                at: DemoData.hoursAgo(94),
                id: 4_440
            ),
            .demo(
                "codecov",
                """
                Coverage on this change: **91.4%** (+2.1%).

                `TileCache.swift` is fully covered except the eviction warning branch.
                """,
                at: DemoData.hoursAgo(25),
                id: 4_441,
                isBot: true
            )
        ],
        reviews: [
            .demo(
                "marcus",
                .commented,
                body: "Not my area, but the coalescing reads well. One question inline.",
                at: DemoData.hoursAgo(48),
                id: 57
            )
        ],
        reviewThreads: [
            .demo(
                "Sources/Waypoint/Map/TileCache.swift",
                line: 27,
                id: 91,
                excerpt: """
                    let task = Task { try await download(key) }
                    inFlight[key] = task
                    """,
                comments: [
                    .demo(
                        "marcus",
                        """
                        If `download` throws, does the failed task stay in `inFlight` for the next
                        caller to await?
                        """,
                        at: DemoData.hoursAgo(48),
                        id: 4_442
                    ),
                    .demo(
                        "priya",
                        "No — the `defer` clears it either way. Added a test for the throwing path.",
                        at: DemoData.hoursAgo(46),
                        id: 4_443
                    )
                ],
                reviewID: 57
            ),
            .demo(
                "Sources/Waypoint/Map/TileCache.swift",
                line: 49,
                id: 92,
                excerpt: """
                    if stale.count > Self.evictionWarningThreshold {
                        logger.notice("evicted \\(stale.count) tiles")
                    """,
                comments: [
                    .demo(
                        viewerLogin,
                        """
                        Is a notice the right level here? A large sweep is expected on the first
                        launch after an upgrade.
                        """,
                        at: DemoData.hoursAgo(29),
                        id: 4_444
                    ),
                    .demo(
                        "priya",
                        "Dropped it to debug and raised the threshold.",
                        at: DemoData.hoursAgo(28),
                        id: 4_445
                    )
                ],
                isResolved: true
            )
        ],
        timelineEvents: [
            .demo(.commit, by: "priya", at: DemoData.hoursAgo(95), detail: "5e10b21 Add a disk-backed tile cache"),
            .demo(.reviewRequested, by: "priya", at: DemoData.hoursAgo(50), detail: viewerLogin),
            .demo(.forcePushed, by: "priya", at: DemoData.hoursAgo(30)),
            .demo(.commit, by: "priya", at: DemoData.hoursAgo(26), detail: "b7d40e8 Coalesce in-flight tile downloads")
        ],
        reactions: [.demo(.eyes, 2)]
    )

    /// An abandoned experiment the viewer reviewed: their own "changes requested", then a close.
    /// No checks — old runs have expired, which is what hides the Checks section entirely.
    static let filterSheetConversation = DemoPullRequestConversation(
        bodyMarkdown: """
            Spike: move the search filters into a bottom sheet instead of the popover.

            Reads well on a phone-sized window and badly on everything else — opening it for the
            discussion, not to merge.
            """,
        createdAt: DemoData.hoursAgo(912),
        changedFiles: 2,
        reviewers: [.demo(viewerLogin, .changesRequested)],
        comments: [
            .demo(
                "ines",
                """
                Closing this. The popover already does everything the sheet does on a desktop-sized
                window, and the detent handling was the bulk of the diff.
                """,
                at: DemoData.hoursAgo(800),
                id: 4_460
            )
        ],
        reviews: [
            .demo(
                viewerLogin,
                .changesRequested,
                body: "The idea is good on small windows. On a wide one the sheet covers the results it filters.",
                at: DemoData.hoursAgo(870),
                id: 41
            )
        ],
        reviewThreads: [
            .demo(
                "Sources/Hummingbird/Search/FilterBottomSheet.swift",
                line: 16,
                id: 98,
                excerpt: "FilterPopover(filters: $filters)",
                comments: [
                    .demo(
                        viewerLogin,
                        "This is the whole argument against the sheet: the fallback is the thing it replaced.",
                        at: DemoData.hoursAgo(870),
                        id: 4_461
                    ),
                    .demo(
                        "ines",
                        "Fair. I'll write up what the sheet was better at and close it.",
                        at: DemoData.hoursAgo(860),
                        id: 4_462
                    )
                ],
                reviewID: 41
            )
        ],
        timelineEvents: [
            .demo(.commit, by: "ines", at: DemoData.hoursAgo(911), detail: "77a1c30 Move filters into a bottom sheet"),
            .demo(.reviewRequested, by: "ines", at: DemoData.hoursAgo(900), detail: viewerLogin),
            .demo(.closed, by: "ines", at: DemoData.hoursAgo(793))
        ]
    )
}
#endif

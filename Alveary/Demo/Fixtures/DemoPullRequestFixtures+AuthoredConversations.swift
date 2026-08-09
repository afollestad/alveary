#if DEBUG
import Foundation

// The conversations on the pull requests the viewer opened — the list screen's Authored tab.
// `DemoPullRequestFixtures+Conversations.swift` owns the shape and the rules these follow.
extension DemoPullRequestFixtures {
    /// The flagship conversation: two reviews with threads nested under them, a body-less carrier
    /// review, a bot comment, an outdated thread, a resolved one, and every bare timeline row.
    static let onboardingConversation = DemoPullRequestConversation(
        bodyMarkdown: """
            ## What changed

            The walkthrough is four steps now — welcome, permissions, a sample trip, then finish —
            with a progress bar across the top and a real transition between them.

            - Adds `OnboardingProgressBar` and `OnboardingStepView`
            - Adds the `sampleTrip` step, seeded from the bundled itinerary
            - Replaces the bare `Continue` button with a per-step title

            ## Testing

            - [x] `swift test`
            - [x] Fresh install on macOS 15 and macOS 26
            - [ ] VoiceOver pass over the progress bar
            """,
        createdAt: DemoData.hoursAgo(48),
        changedFiles: 2,
        checks: [
            .demo("build (macOS)", .passing, url: "https://github.com/demo/waypoint/actions/runs/8814"),
            .demo("swiftlint", .passing),
            .demo("snapshot-tests", .failing, url: "https://github.com/demo/waypoint/actions/runs/8815"),
            .demo("deploy-preview", .pending)
        ],
        reviewers: [
            .demo("priya", .changesRequested, canReRequest: true),
            .demo("marcus", .commented, canReRequest: true),
            .demo("ines", .requested)
        ],
        comments: [
            .demo(
                "priya",
                """
                Pulled this down on a wiped simulator. The step transition is a real improvement —
                the old flow read like four unrelated screens.

                One thing I noticed: the progress bar keeps its filled width for a beat after you
                go back a step.
                """,
                at: DemoData.hoursAgo(30),
                id: 4_401
            )
            .reacting([.demo(.rocket, 2)]),
            .demo(
                "github-actions",
                """
                **Deploy preview** is ready.

                | Step | Result |
                | --- | --- |
                | Build | passed in 2m 41s |
                | Preview | https://preview.waypoint.app/pr-61 |
                """,
                at: DemoData.hoursAgo(23),
                id: 4_402,
                isBot: true
            ),
            .demo(
                viewerLogin,
                """
                Good catch — the bar animates off `completed`, which only grows. Fixed by removing
                the step on the way back rather than leaving it filled.
                """,
                at: DemoData.hoursAgo(19),
                id: 4_403
            )
        ],
        reviews: [
            .demo(
                "priya",
                .changesRequested,
                body: """
                    Structure looks right. Two things below, then I think this is good to go — the
                    transition one is the only real blocker.
                    """,
                at: DemoData.hoursAgo(28),
                id: 51
            ),
            // No body: this renders purely as the header its thread nests under, exactly like
            // GitHub's inline-only "reviewed" row.
            .demo("marcus", .commented, at: DemoData.hoursAgo(20), id: 52),
            .demo(
                "ines",
                .approved,
                body: "Sample-trip step is lovely. Ship it.",
                at: DemoData.minutesAgo(30),
                id: 53
            )
            .reacting([.demo(.hooray, 2)])
        ],
        reviewThreads: [
            .demo(
                "Sources/Waypoint/Onboarding/OnboardingFlow.swift",
                line: 18,
                id: 61,
                excerpt: """
                    OnboardingStepView(step: step)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                    """,
                comments: [
                    .demo(
                        "priya",
                        """
                        A move transition in both directions means going back slides the wrong way.
                        Worth keying it off the travel direction.
                        """,
                        at: DemoData.hoursAgo(28),
                        id: 4_410
                    ),
                    .demo(
                        viewerLogin,
                        """
                        Agreed. I'll thread the direction through `OnboardingStepView` rather than
                        branching inside the modifier.
                        """,
                        at: DemoData.hoursAgo(26),
                        id: 4_411
                    )
                ],
                reviewID: 51
            ),
            .demo(
                "Sources/Waypoint/Onboarding/OnboardingFlow.swift",
                line: 25,
                id: 62,
                excerpt: """
                    private func advance() {
                        completed.insert(step)
                    """,
                comments: [
                    .demo(
                        "priya",
                        "`completed` never shrinks, so back-then-forward leaves the bar over-filled.",
                        at: DemoData.hoursAgo(27),
                        id: 4_412
                    ),
                    .demo(
                        viewerLogin,
                        "Fixed — going back removes the step now.",
                        at: DemoData.hoursAgo(25),
                        id: 4_413
                    )
                ],
                reviewID: 51,
                isResolved: true
            ),
            .demo(
                "Sources/Waypoint/Onboarding/OnboardingStep.swift",
                line: 5,
                id: 63,
                excerpt: """
                    case sampleTrip
                    case finish
                    """,
                comments: [
                    .demo(
                        "marcus",
                        """
                        Inserting a case in the middle rewrites every persisted raw value if this
                        ever gains a `RawRepresentable` conformance. Worth a note on the enum.
                        """,
                        at: DemoData.hoursAgo(20),
                        id: 4_414
                    )
                ],
                reviewID: 52
            ),
            // Standalone and outdated: it keeps its "Outdated" pill on the Overview and is left
            // out of the Changes tab, which cannot place an anchor a force-push moved.
            .demo(
                "Sources/Waypoint/Onboarding/OnboardingFlow.swift",
                line: 22,
                id: 64,
                excerpt: ".animation(.snappy, value: step)",
                comments: [
                    .demo(
                        "priya",
                        """
                        This animated the whole stack, progress bar included. Looks like the
                        force-push already split it out.
                        """,
                        at: DemoData.hoursAgo(29),
                        id: 4_415
                    )
                ],
                isOutdated: true
            )
        ],
        timelineEvents: [
            .demo(.commit, by: viewerLogin, at: DemoData.hoursAgo(47), detail: "8f31c0a Split the walkthrough into four steps"),
            .demo(.reviewRequested, by: viewerLogin, at: DemoData.hoursAgo(46), detail: "priya"),
            .demo(.reviewRequested, by: viewerLogin, at: DemoData.hoursAgo(45), detail: "marcus"),
            .demo(.forcePushed, by: viewerLogin, at: DemoData.hoursAgo(24)),
            .demo(.commit, by: viewerLogin, at: DemoData.hoursAgo(2), detail: "b7d40e8 Add the sample-trip step"),
            .demo(.reviewRequested, by: viewerLogin, at: DemoData.hoursAgo(1), detail: "ines")
        ],
        reactions: [.demo(.thumbsUp, 3), .demo(.hooray, 1, viewerHasReacted: true)]
    )

    /// A short, settled conversation: one approval carrying one resolved thread.
    static let emptyStateConversation = DemoPullRequestConversation(
        bodyMarkdown: """
            Search used to answer a missed query with a grey "No results". It now names the query,
            offers the three nearest suggestions, and keeps the glyph for balance.

            Closes #68.
            """,
        createdAt: DemoData.hoursAgo(24),
        changedFiles: 1,
        checks: [
            .demo("build (iOS)", .passing),
            .demo("unit-tests", .passing)
        ],
        reviewers: [.demo("ines", .approved, canReRequest: true)],
        comments: [
            .demo(
                "ines",
                "Reads much better. Did you get a chance to try it with a long query?",
                at: DemoData.hoursAgo(6),
                id: 4_420
            )
        ],
        reviews: [
            .demo(
                "ines",
                .approved,
                body: "Suggestions are the part that makes this worth doing. Approving.",
                at: DemoData.hoursAgo(5),
                id: 71
            )
        ],
        reviewThreads: [
            .demo(
                "Sources/Hummingbird/Search/SearchEmptyState.swift",
                line: 15,
                id: 72,
                excerpt: """
                    Text("No results for \\(query)")
                        .font(.headline)
                    """,
                comments: [
                    .demo(
                        "ines",
                        """
                        A long query wraps to four or five lines here. Truncating in the middle
                        keeps both ends readable.
                        """,
                        at: DemoData.hoursAgo(5),
                        id: 4_421
                    ),
                    .demo(
                        viewerLogin,
                        "Added a middle truncation and a two-line cap.",
                        at: DemoData.hoursAgo(4.5),
                        id: 4_422
                    )
                ],
                reviewID: 71,
                isResolved: true
            )
        ],
        timelineEvents: [
            .demo(.commit, by: viewerLogin, at: DemoData.hoursAgo(23), detail: "3a91c77 Name the query in the empty state"),
            .demo(.reviewRequested, by: viewerLogin, at: DemoData.hoursAgo(22), detail: "ines")
        ],
        reactions: [.demo(.heart, 1)]
    )

    /// A finished pull request: approval, then the merge row that ends the timeline.
    static let rateLimiterConversation = DemoPullRequestConversation(
        bodyMarkdown: """
            Adds a token-bucket limiter in front of the public API, keyed per client rather than
            globally, and returns `Retry-After` from the bucket's own refill interval.

            Defaults: 600 requests per client per minute, burst of 60.
            """,
        createdAt: DemoData.hoursAgo(216),
        changedFiles: 1,
        checks: [
            .demo("build", .passing),
            .demo("unit-tests", .passing)
        ],
        reviewers: [.demo("marcus", .approved, canReRequest: true)],
        comments: [
            .demo(
                "marcus",
                "Per-client is the right default. Do we have a plan for unauthenticated traffic?",
                at: DemoData.hoursAgo(170),
                id: 4_450
            ),
            .demo(
                viewerLogin,
                "Falls through to the global bucket for now; a separate issue tracks per-IP.",
                at: DemoData.hoursAgo(146),
                id: 4_451
            )
        ],
        reviews: [
            .demo("marcus", .approved, body: "Clean. Approving.", at: DemoData.hoursAgo(150), id: 96)
        ],
        reviewThreads: [
            .demo(
                "Sources/Ledger/Middleware/RateLimiter.swift",
                line: 8,
                id: 97,
                excerpt: """
                    guard let key = request.clientKey else {
                        return true
                    """,
                comments: [
                    .demo(
                        "marcus",
                        "An unauthenticated request bypasses the limiter entirely here.",
                        at: DemoData.hoursAgo(150),
                        id: 4_452
                    ),
                    .demo(
                        viewerLogin,
                        "Tracked separately — the global bucket still applies upstream of this.",
                        at: DemoData.hoursAgo(149),
                        id: 4_453
                    )
                ],
                reviewID: 96,
                isResolved: true
            )
        ],
        timelineEvents: [
            .demo(.commit, by: viewerLogin, at: DemoData.hoursAgo(215), detail: "1d0e4b7 Add a token-bucket rate limiter"),
            .demo(.reviewRequested, by: viewerLogin, at: DemoData.hoursAgo(214), detail: "marcus"),
            .demo(.commit, by: viewerLogin, at: DemoData.hoursAgo(168), detail: "44c9f02 Key buckets by client"),
            .demo(.merged, by: viewerLogin, at: DemoData.hoursAgo(145))
        ],
        reactions: [.demo(.rocket, 4), .demo(.heart, 2, viewerHasReacted: true)]
    )
}
#endif

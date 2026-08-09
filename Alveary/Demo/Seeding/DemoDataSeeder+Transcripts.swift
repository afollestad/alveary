#if DEBUG
import Foundation
import SwiftData

/// One builder per conversation, each its own type-check scope.
///
/// Two grouping rules shape every function here. Consecutive groupable tool calls collapse into a
/// single "Read 3 files" row, and a second pass merges *consecutive* tool groups, standalone
/// tools, sub-agent blocks, and prompt blocks into one activity group — so a message or note is
/// interleaved wherever a standalone tool row should stand on its own.
@MainActor
extension DemoDataSeeder {
    static func seedTripSharingTranscript(
        _ conversation: Conversation,
        design: DemoAttachments,
        capture: DemoAttachments,
        into context: ModelContext
    ) {
        let builder = DemoTranscriptBuilder(conversation: conversation)
        builder.user(
            """
            Add trip sharing: a signed link that opens a read-only itinerary. Start with the link \
            model and the share sheet, and keep revocation out of scope for now.
            """
        )
        builder.assistant(tripSharingPlanMarkdown)
        builder.tool(id: "demo-t1", name: "Read", input: readInput(worktreeFile("Sources/Waypoint/Trips/TripStore.swift")), output: "64 lines")
        builder.tool(id: "demo-t2", name: "Grep", input: #"{"pattern":"ShareLink","output_mode":"files_with_matches"}"#, output: "2 files")
        builder.tool(id: "demo-t3", name: "Read", input: readInput(worktreeFile("Sources/Waypoint/Sharing/ShareSheet.swift")), output: "31 lines")
        builder.assistant("The store already exposes a single-trip fetch, so the read path is a matching predicate rather than a new query.")
        builder.tool(
            id: "demo-t4",
            name: "Bash",
            input: #"{"command":"swift test --filter TripShareLinkTests","description":"Run the sharing tests"}"#,
            output: "Test Suite 'TripShareLinkTests' passed.\n  Executed 3 tests, with 0 failures in 0.412 seconds",
            stderr: "warning: 'waypoint': dependency 'swift-collections' is not used by any target"
        )
        builder.assistant("Tests pass. Tracking the rest of the work:")
        builder.tool(id: "demo-t5", name: "TodoWrite", input: tripSharingTodos, output: "Todos updated")
        appendTripSharingDesignReview(builder, design: design, capture: capture)
        builder.tool(
            id: "demo-t6",
            name: "Edit",
            input: shareSheetEditInput,
            output: "Applied 1 edit to Sources/Waypoint/Sharing/ShareSheet.swift"
        )
        builder.assistant(
            """
            `ShareSheet` now mints the link before rendering, and falls back to a progress view while \
            the mint is in flight. Running the full suite to be sure nothing else reads `trip.title` \
            as a share item.
            """
        )
        builder.tokens(input: 41_820, output: 2_140, cacheRead: 18_400, costUsd: 0.42, model: "claude-opus-5")
        // Trailing call with no result: the in-flight tool row, paired with the busy status dot.
        builder.tool(id: "demo-t7", name: "Bash", input: #"{"command":"swift test","description":"Run the full suite"}"#)
        builder.commit(into: context, endingAt: DemoData.minutesAgo(1))
    }

    /// The flagship's attachment beat, mid-transcript rather than on the opening brief: designs on
    /// one message and the running-build capture on the next, each with its own reply, so neither
    /// bubble reads as a pile of tiles.
    private static func appendTripSharingDesignReview(
        _ builder: DemoTranscriptBuilder,
        design: DemoAttachments,
        capture: DemoAttachments
    ) {
        let designMessage = builder.user("Here's the sheet Ines drew, and the itinerary the link should open onto.")
        designMessage.setPersistedTranscriptAttachments(
            images: design.images,
            persistedAppShots: design.appShots,
            files: design.files
        )
        builder.assistant("That matches the plan — the sheet owns the mint, and the itinerary is the read-only view.")
        let captureMessage = builder.user(
            "And here's the trip screen in the running build. The share button sits below the fold on a short window."
        )
        captureMessage.setPersistedTranscriptAttachments(
            images: capture.images,
            persistedAppShots: capture.appShots,
            files: capture.files
        )
        builder.assistant("Noted — I'll pin the action row once the sheet is wired. Now the share sheet itself.")
    }

    static func seedTripSharingSideTranscript(_ conversation: Conversation, into context: ModelContext) {
        let builder = DemoTranscriptBuilder(conversation: conversation)
        builder.user("Separately — what would revocation cost us? Just the shape, no code yet.")
        builder.assistant(
            """
            Revocation needs a server-side token table, because a signed link is otherwise valid until \
            it expires. That is one migration and one endpoint; the client side is a single row in \
            trip settings.
            """
        )
        builder.tokens(input: 6_120, output: 380, costUsd: 0.06, model: "claude-opus-5")
        builder.commit(into: context, endingAt: DemoData.minutesAgo(22))
    }

    /// The approval thread. Deliberately holds no `AskUserQuestion`: an unanswered question
    /// anywhere in the conversation disables every approval control in it.
    static func seedFlakyMapTestsTranscript(_ conversation: Conversation, into context: ModelContext) {
        let builder = DemoTranscriptBuilder(conversation: conversation)
        builder.user("MapRegionTests fails about one run in five on CI. Find the flake and fix it.")
        builder.assistant("Reproducing under a fixed seed first so the failure is deterministic.")
        // No resolved approval row beside this call: an approval and its own tool call share a
        // toolId and join the same batch card, so the command would be listed twice.
        builder.tool(
            id: "demo-a1",
            name: "Bash",
            input: #"{"command":"swift test --filter MapRegionTests --repeat-until-failure","description":"Reproduce the flake"}"#,
            output: "Failed on iteration 7: expected 3 annotations, found 2"
        )
        builder.assistant(
            """
            Reproduced. The test asserts annotation count before the region's debounce fires, so the \
            third annotation lands after the assertion. Two files need the same fix.
            """
        )
        builder.tokens(input: 22_400, output: 1_180, cacheRead: 9_600, costUsd: 0.21, model: "claude-opus-5")
        // Two same-session, same-family approvals with no result yet: one live batch card.
        for (index, fileName) in ["MapRegionTests.swift", "AnnotationTests.swift"].enumerated() {
            builder.approval(
                id: "demo-a\(index + 2)",
                name: "Edit",
                input: debounceEditInput(fileName),
                sessionID: demoApprovalSession,
                status: "pending"
            )
        }
        // `tool_deferred` is the one stop reason that leaves the approvals above unresolved.
        builder.tokens(input: 24_100, output: 260, cacheRead: 9_600, costUsd: 0.04, model: "claude-opus-5", stopReason: "tool_deferred")
        builder.commit(into: context, endingAt: DemoData.minutesAgo(6))
    }

    /// Plan mode plus the pull-request link prompt. Returns the user message the prompt anchors
    /// to; `pendingPullRequestPromptsJSON` is keyed by that record's id.
    static func seedOnboardingTranscript(
        _ conversation: Conversation,
        into context: ModelContext
    ) -> ConversationEventRecord {
        let builder = DemoTranscriptBuilder(conversation: conversation)
        builder.user("Plan a refactor of the onboarding flow before touching anything.")
        builder.tool(id: "demo-p1", name: "EnterPlanMode", input: "{}", output: "Plan mode enabled")
        builder.assistant("Reading the current flow before proposing anything.")
        builder.tool(
            id: "demo-p2",
            name: "Read",
            input: readInput(projectFile(DemoData.waypointPath, "Sources/Waypoint/Onboarding/OnboardingFlow.swift")),
            output: "212 lines"
        )
        builder.approval(id: "demo-p3", name: "ExitPlanMode", input: onboardingPlanInput, sessionID: demoPlanSession, status: "denied")
        builder.assistant("Staying in plan mode then — folding the permissions step into the same screen and re-proposing.")
        builder.approval(id: "demo-p4", name: "ExitPlanMode", input: onboardingRevisedPlanInput, sessionID: demoPlanSession, status: "approved")
        builder.tool(id: "demo-p5", name: "Edit", input: onboardingEditInput, output: "Applied 3 edits")
        builder.assistant("Done — four screens are now two, and the permission prompt rides the location step.")
        let anchor = builder.user(
            """
            Nice. I opened https://github.com/demo/hummingbird/pull/74 for the search empty state \
            earlier — same pattern, take a look when you get a chance.
            """
        )
        builder.tokens(input: 38_600, output: 3_020, cacheRead: 15_200, costUsd: 0.51, model: "claude-opus-5")
        builder.commit(into: context, endingAt: DemoData.hoursAgo(2))
        return anchor
    }

    /// The Codex thread: a Skill row, a sub-agent block, and the pinned task list.
    static func seedStructuredLoggingTranscript(_ conversation: Conversation, into context: ModelContext) {
        let builder = DemoTranscriptBuilder(conversation: conversation)
        builder.user("Move the ingest worker onto structured logging. Keep the existing log levels.")
        builder.tool(id: "demo-s1", name: "Skill", input: #"{"skill":"migration-audit"}"#, output: "Loaded migration-audit v2.0.1")
        builder.assistant("Fanning out to map every call site before changing the logger itself.")
        builder.toolCall(id: "demo-s2", name: "Agent", input: #"{"subagent_type":"Explore","description":"Map log call sites"}"#)
        builder.tool(id: "demo-s3", name: "Grep", input: #"{"pattern":"logger.log("}"#, output: "34 matches", parentToolUseID: "demo-s2")
        builder.tool(
            id: "demo-s4",
            name: "Read",
            input: readInput(projectFile(DemoData.ledgerPath, "Sources/Ledger/Ingest/Worker.swift")),
            output: "180 lines",
            parentToolUseID: "demo-s2"
        )
        builder.subAgentCompleted(id: "demo-s2", toolUses: 2, totalTokens: 18_400, durationMs: 14_200)
        builder.toolResult(id: "demo-s2", output: "Found 34 call sites across 11 files; 6 pass interpolated strings.")
        builder.assistant("Six call sites interpolate, so those become fields rather than a formatted string.")
        builder.tool(id: "demo-s5", name: "TodoWrite", input: structuredLoggingTodos, output: "Todos updated")
        builder.tokens(input: 51_300, output: 2_760, cacheRead: 21_800, costUsd: 0.38, model: "gpt-5-codex")
        builder.commit(into: context, endingAt: DemoData.hoursAgo(5))
    }

    /// The transcript-notes thread: an error banner plus every note shape that renders.
    static func seedRateLimitTranscript(_ conversation: Conversation, into context: ModelContext) {
        let builder = DemoTranscriptBuilder(conversation: conversation)
        builder.user("Add rate limit middleware to the public API. 100 requests a minute per token.")
        builder.assistant("Starting with the bucket store so the middleware itself stays thin.")
        builder.tool(
            id: "demo-r1",
            name: "Bash",
            input: #"{"command":"swift build","description":"Build after the middleware change"}"#,
            output: "error: cannot find 'RateLimitStore' in scope",
            isError: true
        )
        builder.error("The build failed before the middleware could be wired up.")
        builder.note(type: ConversationEventRecord.stopType, content: ConversationInterruption.displayMessage)
        builder.note(type: ConversationEventRecord.steeredConversationType, content: ConversationSteering.displayMessage)
        builder.assistant("Picking it back up: the store needed to be `Sendable` before the middleware could hold it.")
        builder.note(type: ConversationContextCompaction.completedType, content: ConversationContextCompaction.completedDisplayMessage)
        builder.note(type: ConversationEventRecord.scheduledTaskNoteType, content: "Started by the scheduled task \"Nightly dependency audit\".")
        builder.assistant("Middleware is in and the suite is green. 100 requests a minute, keyed by token, with a `Retry-After` header on rejection.")
        builder.tokens(input: 33_900, output: 1_940, cacheRead: 12_100, costUsd: 0.29, model: "claude-opus-5")
        builder.commit(into: context, endingAt: DemoData.daysAgo(2))
    }

    /// The attachment thread. Design files and the app-shot capture ride two separate messages
    /// with a reply between them: one bubble carrying image tiles, a file chip, and an app-shot
    /// card reads as a pile rather than as two things the user sent.
    static func seedEmptyStatesTranscript(
        _ conversation: Conversation,
        design: DemoAttachments,
        capture: DemoAttachments,
        into context: ModelContext
    ) {
        let builder = DemoTranscriptBuilder(conversation: conversation)
        let designMessage = builder.user(
            "Here's the mock for the new empty states, plus the missing-tile bug I mentioned. Copy is in the notes file."
        )
        designMessage.setPersistedTranscriptAttachments(
            images: design.images,
            persistedAppShots: design.appShots,
            files: design.files
        )
        builder.assistant(
            """
            Got them. Three changes: raise the illustration by 12 points, drop the subtitle to \
            `.secondary`, and give the search variant its own copy instead of reusing the history one.
            """
        )
        let captureMessage = builder.user("Here's the live window too — the copy sits too close to the illustration.")
        captureMessage.setPersistedTranscriptAttachments(
            images: capture.images,
            persistedAppShots: capture.appShots,
            files: capture.files
        )
        builder.assistant("That's the same 12 points. Applying it now.")
        builder.tool(id: "demo-e1", name: "Edit", input: emptyStateEditInput, output: "Applied 2 edits")
        builder.assistant("Spacing and hierarchy are in. The tile gap is a separate fix — it is a cache miss, not a layout bug.")
        builder.tokens(input: 18_700, output: 940, cacheRead: 6_300, costUsd: 0.14, model: "claude-opus-5")
        builder.commit(into: context, endingAt: DemoData.hoursAgo(8))
    }

    static func seedArchivedTranscript(_ conversation: Conversation, into context: ModelContext) {
        let builder = DemoTranscriptBuilder(conversation: conversation)
        builder.user("Spike: would a local vector index be fast enough for trip search?")
        builder.assistant(
            """
            Measured on the 12k-trip fixture: 38 ms cold, 4 ms warm. Fast enough, but the index is \
            180 MB on disk, which is more than the whole app today. Parking this.
            """
        )
        builder.tokens(input: 12_400, output: 620, costUsd: 0.09, model: "claude-opus-5")
        builder.commit(into: context, endingAt: DemoData.daysAgo(12))
    }

    // MARK: Shared inputs

    static let demoApprovalSession = "demo-session-map-tests"
    private static let demoPlanSession = "demo-session-onboarding"

    static func readInput(_ absolutePath: String) -> String {
        #"{"file_path":"\#(absolutePath)"}"#
    }

    static func editInput(_ absolutePath: String, old: String, new: String) -> String {
        #"{"file_path":"\#(absolutePath)","old_string":"\#(old)","new_string":"\#(new)"}"#
    }

    static func worktreeFile(_ relativePath: String) -> String {
        "\(DemoData.tripSharingWorktreePath)/\(relativePath)"
    }

    static func projectFile(_ root: String, _ relativePath: String) -> String {
        "\(root)/\(relativePath)"
    }
}

private extension DemoDataSeeder {
    static let tripSharingPlanMarkdown = """
        Here's the shape for **trip sharing**.

        ## Model

        A share link is a signed token plus an expiry. `TripShareLink` owns both, and `TripStore`
        gains one read path keyed on the token.

        | Piece | File | Change |
        | --- | --- | --- |
        | Link model | `Sharing/TripShareLink.swift` | Added |
        | Share sheet | `Sharing/ShareSheet.swift` | Updated |
        | Store lookup | `Trips/TripStore.swift` | Updated |

        ```swift
        struct TripShareLink: Hashable, Sendable {
            let tripID: Trip.ID
            let token: String
            let expiresAt: Date
        }
        ```

        The sheet waits on the mint before it renders:

        ```diff
        -        ShareLink(item: trip.title)
        +        ShareLink(item: url) { Label("Share trip", systemImage: "square.and.arrow.up") }
        ```

        Still open:

        - Revocation needs a server-side token table
        - The itinerary header should show the expiry
        - Token format wants documenting in [sharing.md](https://waypoint.app/docs/sharing)
        """

    static let tripSharingTodos = """
        {"todos":[\
        {"content":"Add the TripShareLink model","activeForm":"Adding the TripShareLink model","status":"completed"},\
        {"content":"Wire the share sheet to the mint","activeForm":"Wiring the share sheet","status":"completed"},\
        {"content":"Add the token read path to TripStore","activeForm":"Adding the token read path","status":"completed"},\
        {"content":"Cover the link with a unit test","activeForm":"Covering the link with a test","status":"completed"}\
        ]}
        """

    static let structuredLoggingTodos = """
        {"todos":[\
        {"content":"Introduce LogField and the encoder","activeForm":"Introducing LogField","status":"completed"},\
        {"content":"Convert the six interpolated call sites","activeForm":"Converting interpolated call sites","status":"in_progress"},\
        {"content":"Keep the existing level mapping","activeForm":"Keeping the level mapping","status":"pending"},\
        {"content":"Update the ingest runbook","activeForm":"Updating the ingest runbook","status":"pending"}\
        ]}
        """

    // Raw strings throughout: these are JSON payloads, so `\n` and `\"` have to survive into the
    // string rather than being interpreted by Swift.
    static func debounceEditInput(_ fileName: String) -> String {
        editInput(
            projectFile(DemoData.waypointPath, "Tests/WaypointTests/\(fileName)"),
            old: #"XCTAssertEqual(region.annotations.count, 3)"#,
            new: #"try await region.settle()\n        XCTAssertEqual(region.annotations.count, 3)"#
        )
    }

    static let onboardingEditInput = editInput(
        projectFile(DemoData.waypointPath, "Sources/Waypoint/Onboarding/OnboardingFlow.swift"),
        old: #"case valueProp\n    case location\n    case permissions\n    case account"#,
        new: #"case welcome\n    case location"#
    )

    static let emptyStateEditInput = editInput(
        projectFile(DemoData.hummingbirdPath, "Sources/Hummingbird/Search/EmptyStateView.swift"),
        old: #"Text(\"Nothing here\")"#,
        new: #"Text(subtitle)\n                .font(.subheadline)\n                .foregroundStyle(.secondary)"#
    )

    static let shareSheetEditInput = editInput(
        worktreeFile("Sources/Waypoint/Sharing/ShareSheet.swift"),
        old: #"ShareLink(item: trip.title)"#,
        new: #"ShareLink(item: url) { Label(\"Share trip\", systemImage: \"square.and.arrow.up\") }"#
    )

    static let onboardingPlanInput = #"""
        {"plan":"# Refactor the onboarding flow\n\n\#
        Four screens become three: welcome, location, and account.\n\n\#
        1. Merge the value-prop screen into welcome\n\#
        2. Keep the permission prompt on its own screen\n\#
        3. Move account creation last so it can be skipped"}
        """#

    static let onboardingRevisedPlanInput = #"""
        {"plan":"# Refactor the onboarding flow (revised)\n\n\#
        Two screens, with the permission prompt folded into the location step.\n\n\#
        1. **Welcome** — value prop and a single continue action\n\#
        2. **Location** — the map preview requests permission inline\n\#
        3. Account creation moves to a dismissible banner on first launch\n\n\#
        Everything below the fold stays where it is."}
        """#
}
#endif

import XCTest
import SwiftUI

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testAssistantBubble() {
        assertMacSnapshot(
            AssistantBubble(markdown: "Sure thing."),
            size: CGSize(width: 320, height: 170),
            named: "assistant_bubble"
        )
    }

    func testAssistantBubbleCodeBlock() {
        assertMacSnapshot(
            AssistantBubble(markdown: "Here you go:\n```swift\nlet greeting = \"Hello\"\nprint(greeting)\n```"),
            size: CGSize(width: 420, height: 220),
            named: "assistant_bubble_code_block"
        )
    }

    func testAssistantBubbleCodeBlockFillsResolvedMarkdownWidth() {
        assertMacSnapshot(
            AssistantBubble(
                markdown: """
                This line is wider than the small code sample.

                ```swift
                let ok = true
                ```
                """
            ),
            size: CGSize(width: 620, height: 240),
            named: "assistant_bubble_code_block_fills_resolved_markdown_width"
        )
    }

    func testAssistantBubbleWideCodeBlockScrollsInternally() {
        let longCodeLine = #"let message = "This code line is intentionally long enough to exceed the compact assistant bubble width "# +
            #"and require horizontal scrolling.""#

        assertMacSnapshot(
            AssistantBubble(
                markdown: """
                Long code:

                ```swift
                \(longCodeLine)
                ```
                """
            ),
            size: CGSize(width: 460, height: 240),
            named: "assistant_bubble_wide_code_block_scrolls_internally"
        )
    }

    func testAssistantBubbleTable() {
        assertMacSnapshot(
            AssistantBubble(
                markdown: """
                Here is the current status:

                | File | State | Count |
                | :--- | :---: | ---: |
                | `AppMarkdown.swift` | Done | 12 |
                | `SyntaxHighlighter.swift` | Pending | 3 |
                """
            ),
            size: CGSize(width: 620, height: 260),
            named: "assistant_bubble_table"
        )
    }

    func testAssistantBubbleWideTableScrollsInternally() {
        assertMacSnapshot(
            AssistantBubble(
                markdown: """
                | Speaker | Transcript excerpt | Source |
                | :--- | :--- | :--- |
                | Agent | Transcript excerpt is intentionally long enough to overflow compact bubble width. | Rendering/AppMarkdownTable.swift |
                | User | Short reply | Alveary/Views/Chat/ChatSupplementaryViews.swift |
                """
            ),
            size: CGSize(width: 460, height: 260),
            named: "assistant_bubble_wide_table_scrolls_internally"
        )
    }

    func testAssistantBubbleTaskListAndHTML() {
        assertMacSnapshot(
            AssistantBubble(
                markdown: """
                <p><strong>Release checklist</strong></p>

                - [x] Parse <b>HTML</b> emphasis
                - [ ] Render <u>unchecked</u> task rows
                - [ ] Keep `<i>literal</i>` code intact
                """
            ),
            size: CGSize(width: 520, height: 250),
            named: "assistant_bubble_task_list_and_html"
        )
    }

    func testAssistantBubbleHorizontalRuleDoesNotForceMaxWidth() {
        assertMacSnapshot(
            AssistantBubble(
                markdown: """
                Compact content above.

                ---

                Compact content below.
                """
            ),
            size: CGSize(width: 620, height: 220),
            named: "assistant_bubble_horizontal_rule_does_not_force_max_width"
        )
    }

    func testAssistantBubbleInlineCode() {
        assertMacSnapshot(
            AssistantBubble(markdown: "Run `git status` and then `git diff` before the next step."),
            size: CGSize(width: 420, height: 180),
            named: "assistant_bubble_inline_code"
        )
    }

    func testAssistantBubbleWideTranscriptUsesAdaptiveWidthCap() {
        assertMacSnapshot(
            transcriptSizedAssistantBubble(width: 1_200),
            size: CGSize(width: 1_200, height: 260),
            named: "assistant_bubble_wide_transcript_uses_adaptive_width_cap"
        )
    }

    func testAssistantBubbleCompactTranscriptFallsBackToNearEdgeWidth() {
        assertMacSnapshot(
            transcriptSizedAssistantBubble(width: 620),
            size: CGSize(width: 620, height: 260),
            named: "assistant_bubble_compact_transcript_falls_back_to_near_edge_width"
        )
    }

    // Regression guard: lines in a multi-line bubble must keep a uniform line height
    // regardless of whether a line contains an inline-code chip. An over-tall chip
    // placeholder previously expanded only the lines that contained chips, which was
    // visible as extra space between chipped and non-chipped list items.
    func testAssistantBubbleMixedInlineCodeLineHeight() {
        assertMacSnapshot(
            AssistantBubble(
                markdown: """
                Could you clarify what you'd like tested? Options I can think of:

                1. Add a second action to `.alveary.json` that runs `code .` (open the project in VS Code)
                2. Verify the existing `open index.html` command works
                3. Something else
                """
            ),
            size: CGSize(width: 520, height: 220),
            named: "assistant_bubble_mixed_inline_code_line_height"
        )
    }

    func testUserBubbleInlineCode() {
        assertMacSnapshot(
            UserBubble(
                text: "Run `git status` before the next step.",
                showsRetry: false,
                onRetry: nil
            ),
            size: CGSize(width: 420, height: 180),
            named: "user_bubble_inline_code"
        )
    }

    func testUserBubbleRetryableFailure() {
        assertMacSnapshot(
            UserBubble(
                text: "Follow up on the diff refresh issue after the current run.",
                showsRetry: true,
                onRetry: {}
            ),
            size: CGSize(width: 760, height: 180),
            named: "user_bubble_retryable_failure"
        )
    }

    // Mirrors `testAssistantBubbleMixedInlineCodeLineHeight` for the user-bubble rendering
    // path so a regression on either surface (bubble style, composer-chip pipeline,
    // `AppMarkdownParser`) gets caught independently.
    func testUserBubbleMixedInlineCodeLineHeight() {
        assertMacSnapshot(
            UserBubble(
                text: """
                Could you clarify what you'd like tested? Options I can think of:

                1. Add a second action to `.alveary.json` that runs `code .` (open the project in VS Code)
                2. Verify the existing `open index.html` command works
                3. Something else
                """,
                showsRetry: false,
                onRetry: nil
            ),
            size: CGSize(width: 520, height: 220),
            named: "user_bubble_mixed_inline_code_line_height"
        )
    }

    // Dark-mode user-bubble variant to keep the user-bubble inline-code palette (a neutral
    // grayscale chip) distinct from the assistant-bubble palette (accent-tinted) and catch
    // regressions in either.
    func testUserBubbleMixedInlineCodeLineHeightDark() {
        assertMacSnapshot(
            UserBubble(
                text: """
                Could you clarify what you'd like tested? Options I can think of:

                1. Add a second action to `.alveary.json` that runs `code .` (open the project in VS Code)
                2. Verify the existing `open index.html` command works
                3. Something else
                """,
                showsRetry: false,
                onRetry: nil
            ),
            size: CGSize(width: 520, height: 220),
            named: "user_bubble_mixed_inline_code_line_height_dark",
            colorScheme: .dark
        )
    }

    // Dark-mode variant so the inline-code highlight palette stays legible against the
    // darker bubble fill. This previously rendered very low contrast.
    func testAssistantBubbleMixedInlineCodeLineHeightDark() {
        assertMacSnapshot(
            AssistantBubble(
                markdown: """
                Could you clarify what you'd like tested? Options I can think of:

                1. Add a second action to `.alveary.json` that runs `code .` (open the project in VS Code)
                2. Verify the existing `open index.html` command works
                3. Something else
                """
            ),
            size: CGSize(width: 520, height: 220),
            named: "assistant_bubble_mixed_inline_code_line_height_dark",
            colorScheme: .dark
        )
    }

    func testAssistantBubbleLongMarkdownCollapsed() {
        assertMacSnapshot(
            AssistantBubble(markdown: longAssistantMarkdown),
            size: CGSize(width: 620, height: 520),
            named: "assistant_bubble_long_markdown_collapsed"
        )
    }

    func testAssistantBubbleLongMarkdownExpanded() {
        assertMacSnapshot(
            AssistantBubble(markdown: longAssistantMarkdown, initiallyExpanded: true),
            size: CGSize(width: 620, height: 760),
            named: "assistant_bubble_long_markdown_expanded"
        )
    }

    func testTurnInterruptedNote() {
        assertMacSnapshot(
            TurnInterruptedNote(),
            size: CGSize(width: 320, height: 80),
            named: "turn_interrupted_note"
        )
    }

    func testEnteredPlanModeNote() {
        assertMacSnapshot(
            CenteredTranscriptNote(kind: .enteredPlanMode),
            size: CGSize(width: 320, height: 80),
            named: "entered_plan_mode_note"
        )
    }

    func testStayingInPlanModeNote() {
        assertMacSnapshot(
            CenteredTranscriptNote(kind: .stayingInPlanMode),
            size: CGSize(width: 320, height: 80),
            named: "staying_in_plan_mode_note"
        )
    }

    func testStreamingBubble() {
        assertMacSnapshot(
            StreamingBubble(text: "Working through the repo now."),
            size: CGSize(width: 320, height: 170),
            named: "streaming_bubble"
        )
    }

    func testActiveTurnThinkingIndicator() {
        assertMacSnapshot(
            ActiveTurnThinkingIndicator(isAnimated: false),
            size: CGSize(width: 320, height: 80),
            named: "active_turn_thinking_indicator"
        )
    }

    func testUserBubblesStacked() {
        assertMacSnapshot(
            VStack(alignment: .leading, spacing: 6) {
                UserBubble(
                    text: "Sleep for 10 seconds",
                    showsRetry: false,
                    onRetry: nil
                )

                UserBubble(
                    text: "Test",
                    showsRetry: false,
                    onRetry: nil
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading),
            size: CGSize(width: 360, height: 240),
            named: "user_bubbles_stacked"
        )
    }

    func testAssistantBubblesStacked() {
        assertMacSnapshot(
            VStack(alignment: .leading, spacing: 6) {
                AssistantBubble(markdown: "Hi! How can I help you?")
                AssistantBubble(markdown: "Got it — just a test. Let me know if there's anything I can help you with!")
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading),
            size: CGSize(width: 520, height: 260),
            named: "assistant_bubbles_stacked"
        )
    }

    func testUserBubbleCodeBlock() {
        assertMacSnapshot(
            UserBubble(
                text: "Please update this:\n```swift\nlet enabled = true\n```",
                showsRetry: false,
                onRetry: nil
            ),
            size: CGSize(width: 420, height: 220),
            named: "user_bubble_code_block"
        )
    }

    func testUserBubbleSlashAndMentionChips() {
        assertMacSnapshot(
            UserBubble(
                text: "/review-github-pr look at @Alveary/Views/Input/ChatInputField.swift for the new `inlineHint` flow.",
                showsRetry: false,
                onRetry: nil
            ),
            size: CGSize(width: 620, height: 220),
            named: "user_bubble_slash_and_mention_chips"
        )
    }

    // Regression guard: an `@path/to/file` wrapped in backticks must render verbatim as
    // inline code rather than being clobbered by the composer-chip pipeline into a
    // truncated `@file` chip. `composerTextChips` is invoked with the parsed flat string
    // (backticks stripped), so its own code-range filter finds nothing to exclude; the
    // inline-code `inlinePresentationIntent` guard in `attachComposerChips` is the only
    // thing preventing the overwrite.
    func testUserBubbleInlineCodePreservedAgainstComposerChip() {
        assertMacSnapshot(
            UserBubble(
                text: "Inline code wins: `@Alveary/Views/Input/ChatInputField.swift` stays intact.",
                showsRetry: false,
                onRetry: nil
            ),
            size: CGSize(width: 620, height: 160),
            named: "user_bubble_inline_code_preserved_against_composer_chip"
        )
    }

    private func transcriptSizedAssistantBubble(width: CGFloat) -> some View {
        AssistantBubble(
            markdown: """
            The lighthouse had stood on the cliff for nearly two hundred years, and in that time it had seen every kind
            of weather the North Atlantic could muster. On clear nights, its beam swept the dark water in patient, even
            arcs, each rotation a quiet reassurance to the fishing boats scattered along the coast. On storm nights, the
            same beam fought through curtains of rain and spray, catching glimpses of whitecaps and gulls tumbling
            sideways in the wind.
            """
        )
        .environment(\.transcriptBubbleMaxWidth, adaptiveTranscriptBubbleMaxWidth(for: width))
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var longAssistantMarkdown: String {
        """
        # Implementation Plan

        Render the plan markdown before the user decides whether to leave plan mode.

        ## Transcript

        The plan should appear as normal assistant markdown so headings, lists, links, and inline code all use the same
        rendering path as every other assistant response. Collapsing should be visual only, which means the markdown string
        stays intact and the rendered view is clipped after layout.

        ## Approval

        The approval card remains focused on the decision:

        - `Leave plan mode` approves the deferred tool.
        - `Keep planning` denies it and leaves the session in plan mode.
        - Resolved rows continue to show their persisted approval state.

        ## Validation

        Snapshot coverage should include collapsed and expanded long markdown bubbles so future changes cannot silently
        remove the height cap or the explicit expanded test hook.

        ## Review Details

        The fixture intentionally crosses the assistant bubble cap while staying small enough for snapshot review:

        - Headings should keep their markdown typography.
        - Inline code like `ToolApprovalRequest.planMarkdown` should render normally.
        - List markers should remain aligned before and after expansion.
        - The control row should sit below the faded content without introducing a nested scroll surface.
        """
    }
}

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
}

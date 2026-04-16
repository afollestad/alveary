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

    func testTurnInterruptedNote() {
        assertMacSnapshot(
            TurnInterruptedNote(),
            size: CGSize(width: 320, height: 80),
            named: "turn_interrupted_note"
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
            ActiveTurnThinkingIndicator(),
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
}

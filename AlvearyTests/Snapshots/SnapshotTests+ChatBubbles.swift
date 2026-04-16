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
}

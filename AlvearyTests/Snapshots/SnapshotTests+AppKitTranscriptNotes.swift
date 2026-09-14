import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    /// A relayed prompt's sender renders as a note at the bubble's trailing edge, above it, so
    /// the bubble holds only what the other thread sent.
    func testAppKitTranscriptRelayedPromptNote() async {
        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.bubbleMaxWidth = 560
        let items: [ChatItem] = [
            .assistantMessage(id: "assistant", text: "The migration looks clean so far."),
            .transcriptNote(id: "relayed-user", kind: .relayedPrompt(threadName: "Nightly audit")),
            .userMessage(id: "user", text: "Summarize what changed in the transcript migration.")
        ]
        await prepareTranscriptSnapshotMarkdown(items, configuration: configuration)

        assertMacSnapshot(
            AppKitTranscriptScrollViewRepresentable(
                items: items,
                transientRows: .init(isTurnActive: false, isThinkingAnimated: false),
                rowConfiguration: configuration,
                isFollowing: false,
                scrollToBottomRequest: 0
            ),
            size: CGSize(width: 820, height: 220),
            named: "appkit_transcript_relayed_prompt_note"
        )
    }
}

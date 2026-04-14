import XCTest

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

    func testStreamingBubble() {
        assertMacSnapshot(
            StreamingBubble(text: "Working through the repo now."),
            size: CGSize(width: 320, height: 170),
            named: "streaming_bubble"
        )
    }
}

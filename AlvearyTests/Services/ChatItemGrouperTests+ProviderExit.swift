import XCTest

@testable import Alveary

@MainActor
final class ChatItemGrouperProviderExitTests: XCTestCase {
    func testProviderExitStopRendersCenteredTranscriptNote() {
        let grouper = ChatItemGrouper()
        let message = ConversationProviderExit.displayMessage(providerId: .claude, exitCode: 1)
        let event = ConversationEventRecord(
            id: "provider-exit",
            conversationId: "conversation-1",
            type: "stop",
            content: message
        )

        grouper.update(events: [event])

        XCTAssertEqual(grouper.items, [.transcriptNote(id: "provider-exit", kind: .providerExited(message))])
        XCTAssertEqual(TranscriptNoteKind.providerExited(message).text, "Claude Code exited unexpectedly (exit code 1)")
        XCTAssertEqual(TranscriptNoteKind.providerExited(message).alignment, .centered)
    }
}

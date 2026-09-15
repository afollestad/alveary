import XCTest

@testable import Alveary

@MainActor
final class ChatItemGrouperHarnessExitTests: XCTestCase {
    func testHarnessExitStopRendersCenteredTranscriptNote() {
        let grouper = ChatItemGrouper()
        let message = ConversationHarnessExit.displayMessage(harnessId: .claude, exitCode: 1)
        let event = ConversationEventRecord(
            id: "provider-exit",
            conversationId: "conversation-1",
            type: "stop",
            content: message
        )

        grouper.update(events: [event])

        XCTAssertEqual(grouper.items, [.transcriptNote(id: "provider-exit", kind: .harnessExited(message))])
        XCTAssertEqual(TranscriptNoteKind.harnessExited(message).text, "Claude Code exited unexpectedly (exit code 1)")
        XCTAssertEqual(TranscriptNoteKind.harnessExited(message).alignment, .centered)
    }
}

import XCTest

@testable import Alveary

@MainActor
extension ChatItemGrouperTests {
    /// A relayed user row renders as a note naming the sender followed by a bubble holding only
    /// the prompt — from persisted records and from a live local insert alike — while a row the
    /// user typed gets no note.
    func testRelayedUserRowGetsASenderNoteAboveItsBubble() {
        let grouper = ChatItemGrouper()
        grouper.update(events: [
            ConversationEventRecord(
                id: "row-1",
                conversationId: "conv",
                type: ConversationEventRecord.messageType,
                role: ConversationEventRecord.userRole,
                content: "Summarize your progress.",
                relayedFromConversationId: "planner-main",
                relayedFromThreadName: "Nightly audit"
            )
        ])
        assertRelayedRow(grouper.items, id: "row-1", threadName: "Nightly audit", text: "Summarize your progress.")

        let live = ChatItemGrouper()
        live.appendLocalUserMessage(id: "row-2", text: "Hello", relayedFromThreadName: "Planner")
        assertRelayedRow(live.items, id: "row-2", threadName: "Planner", text: "Hello")
        XCTAssertEqual(live.processedCount, 1)

        let typed = ChatItemGrouper()
        typed.appendLocalUserMessage(id: "row-3", text: "Hi")
        XCTAssertEqual(typed.items.map(\.id), ["row-3"])

        let kind = TranscriptNoteKind.relayedPrompt(threadName: "Planner")
        XCTAssertEqual(kind.text, "From thread “Planner”")
        XCTAssertEqual(kind.alignment, .userBubbleTrailing)
    }

    private func assertRelayedRow(_ items: [ChatItem], id: String, threadName: String, text: String) {
        XCTAssertEqual(items.map(\.id), ["relayed-\(id)", id])
        guard case .transcriptNote(_, .relayedPrompt(let noteThreadName))? = items.first,
              case .userMessage(_, let bubbleText)? = items.last else {
            return XCTFail("Expected a relayed note above a user bubble, got \(items)")
        }
        XCTAssertEqual(noteThreadName, threadName)
        XCTAssertEqual(bubbleText, text)
    }
}

import XCTest

@testable import Alveary

@MainActor
extension ChatItemGrouperTests {
    func testFullRebuildOfLongTranscriptMatchesIncrementalAppends() {
        let events = longTranscriptEvents(turnCount: 1_000)
        let incremental = ChatItemGrouper()
        for event in events.dropLast() {
            incremental.append(event: event)
        }
        let revisionBeforeCompletion = incremental.itemsRevision
        incremental.append(event: events[events.count - 1])
        let rebuilt = ChatItemGrouper()

        rebuilt.update(events: events, forceFullRebuild: true)

        XCTAssertEqual(rebuilt.items, incremental.items)
        // Completing the list rewrites its block in place; caches keyed on the revision must see it.
        XCTAssertGreaterThan(incremental.itemsRevision, revisionBeforeCompletion)
        // Both `TodoWrite` records land in one block, which stays pinned below every row appended
        // while it was incomplete and is completed in place at the end.
        XCTAssertEqual(rebuilt.items.count, events.count - 1)
        let taskListIndices = rebuilt.items.indices.filter { rebuilt.items[$0].isTaskListBlock }
        XCTAssertEqual(taskListIndices, [rebuilt.items.count - 1])
        guard case .taskListBlock(_, let tasks) = rebuilt.items[rebuilt.items.count - 1] else {
            return XCTFail("Expected a task list block")
        }
        XCTAssertEqual(tasks.map(\.status), [.completed])
        XCTAssertEqual(rebuilt.items[rebuilt.items.count - 2].id, "assistant-999")
    }

    func testFullRebuildOfLongTranscriptStaysLinear() {
        let events = longTranscriptEvents(turnCount: 1_500)
        let grouper = ChatItemGrouper()

        measure(metrics: [XCTClockMetric()]) {
            grouper.update(events: events, forceFullRebuild: true)
        }

        XCTAssertEqual(grouper.items.count, events.count - 1)
    }

    /// Alternating user and assistant turns, a `TodoWrite` list opened at the start and completed at
    /// the end, so both the pinned-tail scan and the approval prune run on every appended row.
    private func longTranscriptEvents(turnCount: Int) -> [ConversationEventRecord] {
        let conversationId = "conversation-1"
        var events: [ConversationEventRecord] = []
        events.append(ConversationEventRecord(
            id: "todo-open",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "todo-list",
            toolName: "TodoWrite",
            toolInput: #"{ "todos": [{ "content": "Answer everything", "status": "in_progress" }] }"#
        ))
        for turn in 0..<turnCount {
            events.append(ConversationEventRecord(
                id: "user-\(turn)",
                conversationId: conversationId,
                type: "message",
                role: "user",
                content: "Question \(turn)"
            ))
            events.append(ConversationEventRecord(
                id: "assistant-\(turn)",
                conversationId: conversationId,
                type: "message",
                role: "assistant",
                content: "Answer \(turn)"
            ))
        }
        events.append(ConversationEventRecord(
            id: "todo-close",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "todo-list",
            toolName: "TodoWrite",
            toolInput: #"{ "todos": [{ "content": "Answer everything", "status": "completed" }] }"#
        ))
        return events
    }
}

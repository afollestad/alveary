import XCTest

@testable import Alveary

@MainActor
final class ChatItemGrouperTests: XCTestCase {
    func testAppendThenFullRebuildKeepsTranscriptStable() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let userMessage = ConversationEventRecord(
            id: "user-message",
            conversationId: conversationId,
            type: "message",
            role: "user",
            content: "Hello"
        )
        let assistantMessage = ConversationEventRecord(
            id: "assistant-message",
            conversationId: conversationId,
            type: "message",
            role: "assistant",
            content: "Hi"
        )

        grouper.append(event: userMessage)
        grouper.append(event: assistantMessage)
        grouper.update(events: [userMessage, assistantMessage], forceFullRebuild: true)

        XCTAssertEqual(
            grouper.items,
            [
                .userMessage(id: "user-message", text: "Hello"),
                .assistantMessage(id: "assistant-message", text: "Hi")
            ]
        )
    }

    func testLateToolResultPatchesExistingWorkingBlock() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let toolCall = ConversationEventRecord(
            id: "tool-call",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"git status\"}"
        )
        let thinking = ConversationEventRecord(
            id: "thinking",
            conversationId: conversationId,
            type: "thinking",
            content: "Working"
        )
        let toolResult = ConversationEventRecord(
            id: "tool-result",
            conversationId: conversationId,
            type: "tool_result",
            toolId: "tool-1",
            toolOutput: "clean"
        )

        grouper.update(events: [toolCall, thinking])
        grouper.update(events: [toolCall, thinking, toolResult])

        guard case .workingBlock(_, let tools) = grouper.items[0] else {
            return XCTFail("Expected a working block")
        }
        XCTAssertEqual(tools[0].output, "clean")
        XCTAssertEqual(grouper.items[1], .thinking(id: "thinking", text: "Working"))
    }

    func testPromptToolResultIsSuppressedAndMarkPromptAnsweredPatchesPrompt() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let promptCall = ConversationEventRecord(
            id: "prompt-call",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: "{\"questions\":[{\"question\":\"Pick one\",\"options\":[{\"label\":\"A\",\"description\":\"First\"}]}]}"
        )
        let suppressedResult = ConversationEventRecord(
            id: "prompt-result",
            conversationId: conversationId,
            type: "tool_result",
            toolId: "prompt-1",
            toolOutput: "Answer questions?",
            isError: true
        )

        grouper.update(events: [promptCall, suppressedResult])
        grouper.markPromptAnswered(promptId: "prompt-1", summary: "A")

        XCTAssertEqual(grouper.items.count, 1)
        guard case .promptBlock(_, let prompt) = grouper.items[0] else {
            return XCTFail("Expected a prompt block")
        }
        XCTAssertEqual(prompt.id, "prompt-1")
        XCTAssertEqual(prompt.questions.first?.question, "Pick one")
        XCTAssertEqual(prompt.submittedSummary, "A")
    }
}

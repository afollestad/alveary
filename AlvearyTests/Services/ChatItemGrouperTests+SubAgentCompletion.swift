import XCTest

@testable import Alveary

@MainActor
extension ChatItemGrouperTests {
    func testSubAgentToolResultAlsoCompletesVisibleToolWithSameId() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"

        grouper.handleSubAgentControl(.subAgentStarted(
            toolUseId: "agent-1",
            description: "Regenerate project, run all affected suites",
            taskType: "explorer"
        ))
        grouper.append(event: bashCall(conversationId: conversationId, toolId: "agent-1"))
        grouper.append(event: bashResult(conversationId: conversationId, toolId: "agent-1", output: "failed_tests: 4"))

        let tool = visibleTool(in: grouper, id: "agent-1")
        XCTAssertTrue(tool?.isComplete == true)
        XCTAssertEqual(tool?.output, "failed_tests: 4")
        XCTAssertFalse(tool?.noOutputExpected == true)
    }

    func testSubAgentCompletionMarkerTerminalizesVisibleToolWithoutOutput() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"

        grouper.append(event: bashCall(conversationId: conversationId, toolId: "agent-1"))
        grouper.append(event: subAgentCompletionMarker(
            conversationId: conversationId,
            toolId: "agent-1",
            status: "completed"
        ))

        let tool = visibleTool(in: grouper, id: "agent-1")
        XCTAssertTrue(tool?.isComplete == true)
        XCTAssertTrue(tool?.noOutputExpected == true)
        XCTAssertFalse(tool?.isError == true)
        XCTAssertNil(tool?.output)
    }

    func testFailedSubAgentCompletionMarkerTerminalizesVisibleToolAsError() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"

        grouper.append(event: bashCall(conversationId: conversationId, toolId: "agent-1"))
        grouper.append(event: subAgentCompletionMarker(
            conversationId: conversationId,
            toolId: "agent-1",
            status: "failed"
        ))

        let tool = visibleTool(in: grouper, id: "agent-1")
        XCTAssertTrue(tool?.isComplete == true)
        XCTAssertTrue(tool?.isError == true)
        XCTAssertTrue(tool?.noOutputExpected == true)
    }

    func testSubAgentCompletionMarkerBeforeToolCallTerminalizesLaterVisibleTool() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"

        grouper.append(event: subAgentCompletionMarker(
            conversationId: conversationId,
            toolId: "agent-1",
            status: "interrupted"
        ))
        grouper.append(event: bashCall(conversationId: conversationId, toolId: "agent-1"))

        let tool = visibleTool(in: grouper, id: "agent-1")
        XCTAssertTrue(tool?.isComplete == true)
        XCTAssertTrue(tool?.isInterrupted == true)
        XCTAssertFalse(tool?.isError == true)
        XCTAssertTrue(tool?.noOutputExpected == true)
    }

    func testRealToolResultReplacesPriorNoOutputTerminalState() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"

        grouper.append(event: bashCall(conversationId: conversationId, toolId: "agent-1"))
        grouper.append(event: subAgentCompletionMarker(
            conversationId: conversationId,
            toolId: "agent-1",
            status: "completed"
        ))
        grouper.append(event: bashResult(conversationId: conversationId, toolId: "agent-1", output: "real output"))

        let tool = visibleTool(in: grouper, id: "agent-1")
        XCTAssertTrue(tool?.isComplete == true)
        XCTAssertEqual(tool?.output, "real output")
        XCTAssertFalse(tool?.noOutputExpected == true)
    }

    private func visibleTool(in grouper: ChatItemGrouper, id: String) -> ToolEntry? {
        for item in grouper.items.reversed() {
            switch item {
            case .standaloneTool(_, let tool) where tool.id == id:
                return tool
            case .toolGroup(_, let tools):
                if let tool = tools.first(where: { $0.id == id }) {
                    return tool
                }
            default:
                continue
            }
        }
        return nil
    }

    private func bashCall(conversationId: String, toolId: String) -> ConversationEventRecord {
        ConversationEventRecord(
            id: "\(toolId)-bash-call",
            conversationId: conversationId,
            type: "tool_call",
            toolId: toolId,
            toolName: "Bash",
            toolInput: "{\"command\":\"xcodegen generate && ./scripts/test.sh\"}"
        )
    }

    private func bashResult(conversationId: String, toolId: String, output: String) -> ConversationEventRecord {
        ConversationEventRecord(
            id: "\(toolId)-bash-result",
            conversationId: conversationId,
            type: "tool_result",
            toolId: toolId,
            toolOutput: output
        )
    }

    private func subAgentCompletionMarker(
        conversationId: String,
        toolId: String,
        status: String
    ) -> ConversationEventRecord {
        let payload = SubAgentCompletionMarkerPayload(status: status, toolUses: 1, totalTokens: 100)
        let data = try? JSONEncoder().encode(payload)
        return ConversationEventRecord(
            id: "completion-\(toolId)",
            conversationId: conversationId,
            type: ConversationEventRecord.subAgentCompletedType,
            content: data.flatMap { String(data: $0, encoding: .utf8) },
            toolId: toolId,
            durationMs: 200
        )
    }
}

import XCTest

@testable import Alveary

@MainActor
extension ChatItemGrouperTests {
    func testCommandExecutionSummaryFormatsCanonicalCommand() {
        let summary = ChatItemGrouper.toolSummary(
            name: "CommandExecution",
            input: #"{"command":"swift test","commandActions":[{"command":"ignored"}]}"#
        )
        XCTAssertEqual(summary, "Executing `swift test`")

        let missingCommand = ChatItemGrouper.toolSummary(
            name: "CommandExecution",
            input: #"{"command":"   ","commandActions":[{"command":"git status"}]}"#
        )
        XCTAssertEqual(missingCommand, "CommandExecution")

        let fallbackTool = ToolEntry(
            id: "cmd",
            name: "CommandExecution",
            summary: missingCommand,
            input: #"{"command":"   "}"#,
            output: nil,
            stderr: nil,
            isComplete: false,
            isInterrupted: false,
            isImage: false,
            noOutputExpected: false,
            isError: false
        )
        XCTAssertEqual(fallbackTool.transcriptDisplaySummary, "CommandExecution")

        let genericSummaryWithCommandInput = ToolEntry(
            id: "cmd",
            name: "CommandExecution",
            summary: "CommandExecution",
            input: #"{"command":"swift test"}"#,
            output: nil,
            stderr: nil,
            isComplete: false,
            isInterrupted: false,
            isImage: false,
            noOutputExpected: false,
            isError: false
        )
        XCTAssertEqual(genericSummaryWithCommandInput.transcriptDisplaySummary, "Running `swift test`")
    }

    func testConsecutiveCommandExecutionsStayStandalone() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let first = ConversationEventRecord(
            id: "cmd-1",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "cmd-1",
            toolName: "CommandExecution",
            toolInput: #"{"command":"swift test"}"#
        )
        let second = ConversationEventRecord(
            id: "cmd-2",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "cmd-2",
            toolName: "CommandExecution",
            toolInput: #"{"command":"git status"}"#
        )

        grouper.update(events: [first, second])

        XCTAssertEqual(grouper.items.count, 2)
        for item in grouper.items {
            guard case .standaloneTool = item else {
                return XCTFail("Expected consecutive CommandExecution tools to stay standalone")
            }
        }
    }
}

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

    func testInterruptedStopTerminalizesRunningCommandExecution() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let command = ConversationEventRecord(
            id: "cmd-1",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "cmd-1",
            toolName: "CommandExecution",
            toolInput: #"{"command":"swift test"}"#
        )
        let stop = ConversationEventRecord(
            id: "stop-1",
            conversationId: conversationId,
            type: "stop",
            content: ConversationInterruption.displayMessage
        )

        grouper.update(events: [command, stop])

        XCTAssertEqual(grouper.items.count, 2)
        guard case .standaloneTool(_, let tool) = grouper.items[0] else {
            return XCTFail("Expected the running command to remain a standalone tool row")
        }
        XCTAssertTrue(tool.isComplete)
        XCTAssertTrue(tool.isInterrupted)
        XCTAssertFalse(tool.isError)
        XCTAssertFalse(tool.transcriptDisplaySummary.hasPrefix("Running "))
        XCTAssertEqual(grouper.items[1], .transcriptNote(id: "stop-1", kind: .interrupted))
    }

    func testTerminalizingIncompleteToolsAsInterruptedUpdatesVisibleToolRows() {
        let historicalCommand = commandTool(id: "old-cmd-1", isComplete: false)
        let runningCommand = commandTool(id: "cmd-1", isComplete: false)
        let completedRead = genericTool(id: "read-1", name: "Read", isComplete: true)
        let runningGrep = genericTool(id: "grep-1", name: "Grep", isComplete: false)

        let items: [ChatItem] = [
            .standaloneTool(id: "tool-old-cmd-1", tool: historicalCommand),
            .userMessage(id: "user-2", text: "Next turn"),
            .standaloneTool(id: "tool-cmd-1", tool: runningCommand),
            .toolGroup(id: "group-read-1", tools: [completedRead, runningGrep])
        ].interruptedToolsTerminalized

        guard case .standaloneTool(_, let oldCommand) = items[0],
              case .standaloneTool(_, let updatedCommand) = items[2],
              case .toolGroup(_, let updatedTools) = items[3] else {
            return XCTFail("Expected terminalized standalone and grouped tool rows")
        }
        XCTAssertEqual(oldCommand, historicalCommand)
        XCTAssertTrue(updatedCommand.isComplete)
        XCTAssertTrue(updatedCommand.isInterrupted)
        XCTAssertEqual(updatedCommand.transcriptDisplaySummary, "Ran `swift test`")
        XCTAssertEqual(updatedTools[0], completedRead)
        XCTAssertTrue(updatedTools[1].isComplete)
        XCTAssertTrue(updatedTools[1].isInterrupted)
    }

    private func commandTool(id: String, isComplete: Bool) -> ToolEntry {
        ToolEntry(
            id: id,
            name: "CommandExecution",
            summary: "Executing `swift test`",
            input: #"{"command":"swift test"}"#,
            output: isComplete ? "ok" : nil,
            stderr: nil,
            isComplete: isComplete,
            isInterrupted: false,
            isImage: false,
            noOutputExpected: false,
            isError: false
        )
    }

    private func genericTool(id: String, name: String, isComplete: Bool) -> ToolEntry {
        ToolEntry(
            id: id,
            name: name,
            summary: "\(name) `File.swift`",
            input: "{}",
            output: isComplete ? "ok" : nil,
            stderr: nil,
            isComplete: isComplete,
            isInterrupted: false,
            isImage: false,
            noOutputExpected: false,
            isError: false
        )
    }
}

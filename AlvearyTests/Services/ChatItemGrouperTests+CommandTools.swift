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

    func testCommandExecutionResultBeforeCallCompletesLaterVisibleRow() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let result = commandResultRecord(
            id: "cmd-result",
            toolId: "cmd-1",
            conversationId: conversationId,
            output: ""
        )
        let call = commandCallRecord(
            id: "cmd-call",
            toolId: "cmd-1",
            conversationId: conversationId,
            command: "pwd"
        )

        grouper.update(events: [result, call])

        XCTAssertEqual(grouper.items.count, 1)
        guard case .standaloneTool(_, let tool) = grouper.items[0] else {
            return XCTFail("Expected the later command call to consume the cached result")
        }
        XCTAssertTrue(tool.isComplete)
        XCTAssertEqual(tool.output, "")
        XCTAssertEqual(tool.transcriptDisplaySummary, "Ran `pwd`")
        XCTAssertTrue(grouper.pendingToolResultEventsByToolId.isEmpty)
    }

    func testAppendingCommandExecutionResultBeforeCallCompletesLaterVisibleRow() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"

        grouper.append(event: commandResultRecord(
            id: "cmd-result",
            toolId: "cmd-1",
            conversationId: conversationId,
            output: "/tmp/project\n"
        ))
        grouper.append(event: commandCallRecord(
            id: "cmd-call",
            toolId: "cmd-1",
            conversationId: conversationId,
            command: "pwd"
        ))

        XCTAssertEqual(grouper.items.count, 1)
        guard case .standaloneTool(_, let tool) = grouper.items[0] else {
            return XCTFail("Expected the later command call to consume the cached result")
        }
        XCTAssertTrue(tool.isComplete)
        XCTAssertEqual(tool.output, "/tmp/project\n")
        XCTAssertEqual(tool.transcriptDisplaySummary, "Ran `pwd`")
        XCTAssertTrue(grouper.pendingToolResultEventsByToolId.isEmpty)
    }

    func testFileChangeSummariesHandleKnownAndUnknownKinds() throws {
        let addInput = try fileChangeInput(changes: [
            fileChange(path: "/tmp/notes.md", kind: ["type": "add"], diff: "# Notes")
        ])
        let deleteInput = try fileChangeInput(changes: [
            fileChange(path: "/tmp/old.md", kind: ["type": "delete"], diff: "# Old")
        ])
        let updateInput = try fileChangeInput(changes: [
            fileChange(path: "/tmp/new.md", kind: ["type": "update", "move_path": "/tmp/old.md"], diff: "@@ -1 +1 @@")
        ])
        let unknownInput = try fileChangeInput(changes: [
            fileChange(path: "/tmp/config.toml", kind: ["type": "rewrite"], diff: "value = true")
        ])
        let multiInput = try fileChangeInput(changes: [
            fileChange(path: "/tmp/a.md", kind: ["type": "add"], diff: "A"),
            fileChange(path: "/tmp/b.md", kind: ["type": "delete"], diff: "B")
        ])
        let partiallyMalformedInput = try fileChangeInput(changes: [
            fileChange(path: "/tmp/a.md", kind: ["type": "add"], diff: "A"),
            ["path": "/tmp/b.md", "kind": ["type": "delete"]]
        ])

        XCTAssertEqual(ChatItemGrouper.toolSummary(name: "FileChange", input: addInput), "Adding `notes.md`")
        XCTAssertEqual(fileChangeTool(input: addInput, isComplete: true).transcriptDisplaySummary, "Added `notes.md`")
        XCTAssertEqual(fileChangeTool(input: deleteInput).transcriptDisplaySummary, "Deleting `old.md`")
        XCTAssertEqual(fileChangeTool(input: deleteInput, isComplete: true).transcriptDisplaySummary, "Deleted `old.md`")
        XCTAssertEqual(fileChangeTool(input: updateInput).transcriptDisplaySummary, "Moving `old.md` to `new.md`")
        XCTAssertEqual(fileChangeTool(input: updateInput, isComplete: true).transcriptDisplaySummary, "Moved `old.md` to `new.md`")
        XCTAssertEqual(fileChangeTool(input: unknownInput).transcriptDisplaySummary, "Changing `config.toml`")
        XCTAssertEqual(fileChangeTool(input: unknownInput, isComplete: true).transcriptDisplaySummary, "Changed `config.toml`")
        XCTAssertEqual(fileChangeTool(input: multiInput).transcriptDisplaySummary, "Changing 2 files")
        XCTAssertEqual(fileChangeTool(input: multiInput, isComplete: true).transcriptDisplaySummary, "Changed 2 files")
        XCTAssertEqual(ChatItemGrouper.toolSummary(name: "FileChange", input: partiallyMalformedInput), "FileChange")
    }

    func testFileChangeStaysStandaloneAndResultUpdatesVisibleRow() throws {
        XCTAssertEqual(ChatItemGrouper.groupability(forToolNamed: "FileChange"), .standalone)

        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let call = ConversationEventRecord(
            id: "file-change-call",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "file-change-1",
            toolName: "FileChange",
            toolInput: try fileChangeInput(changes: [
                fileChange(path: "/tmp/notes.md", kind: ["type": "add"], diff: "# Notes")
            ])
        )
        let result = ConversationEventRecord(
            id: "file-change-result",
            conversationId: conversationId,
            type: "tool_result",
            toolId: "file-change-1",
            toolOutput: "/tmp/notes.md\nkind: add\n# Notes"
        )

        grouper.update(events: [call, result])

        XCTAssertEqual(grouper.items.count, 1)
        guard case .standaloneTool(_, let tool) = grouper.items[0] else {
            return XCTFail("Expected FileChange to render as a standalone tool")
        }
        XCTAssertEqual(tool.name, "FileChange")
        XCTAssertTrue(tool.isComplete)
        XCTAssertEqual(tool.output, "/tmp/notes.md\nkind: add\n# Notes")
        XCTAssertEqual(tool.transcriptDisplaySummary, "Added `notes.md`")
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
        ].interruptedActivityTerminalized

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

    private func commandCallRecord(
        id: String,
        toolId: String,
        conversationId: String,
        command: String
    ) -> ConversationEventRecord {
        ConversationEventRecord(
            id: id,
            conversationId: conversationId,
            type: "tool_call",
            toolId: toolId,
            toolName: "CommandExecution",
            toolInput: #"{"command":"\#(command)"}"#
        )
    }

    private func commandResultRecord(
        id: String,
        toolId: String,
        conversationId: String,
        output: String
    ) -> ConversationEventRecord {
        ConversationEventRecord(
            id: id,
            conversationId: conversationId,
            type: "tool_result",
            toolId: toolId,
            toolOutput: output
        )
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

    private func fileChangeTool(input: String, isComplete: Bool = false) -> ToolEntry {
        ToolEntry(
            id: "file-change-1",
            name: "FileChange",
            summary: ChatItemGrouper.toolSummary(name: "FileChange", input: input),
            input: input,
            output: isComplete ? "ok" : nil,
            stderr: nil,
            isComplete: isComplete,
            isInterrupted: false,
            isImage: false,
            noOutputExpected: false,
            isError: false
        )
    }

    private func fileChange(path: String, kind: [String: Any], diff: String) -> [String: Any] {
        [
            "path": path,
            "kind": kind,
            "diff": diff
        ]
    }

    private func fileChangeInput(changes: [[String: Any]]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["changes": changes], options: [.sortedKeys])
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }
}

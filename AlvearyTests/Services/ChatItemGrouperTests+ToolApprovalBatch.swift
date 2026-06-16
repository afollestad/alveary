import XCTest

@testable import Alveary

extension ChatItemGrouperTests {
    func testParallelToolApprovalsRenderAsSingleBatchBlock() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let sessionId = "session-123"
        let pwdCall = bashToolCall(id: "pwd-call", conversationId: conversationId, toolId: "tool-pwd", command: "pwd")
        let pwdApproval = bashToolApproval(
            id: "pwd-approval",
            conversationId: conversationId,
            sessionId: sessionId,
            toolId: "tool-pwd",
            command: "pwd"
        )
        let dateCall = bashToolCall(id: "date-call", conversationId: conversationId, toolId: "tool-date", command: "date")
        let dateApproval = bashToolApproval(
            id: "date-approval",
            conversationId: conversationId,
            sessionId: sessionId,
            toolId: "tool-date",
            command: "date"
        )

        grouper.update(events: [pwdCall, pwdApproval, dateCall, dateApproval])

        XCTAssertEqual(grouper.items.count, 3)
        guard case .standaloneTool(_, let firstTool) = grouper.items[0] else {
            return XCTFail("Expected first tool row")
        }
        XCTAssertEqual(firstTool.id, "tool-pwd")
        XCTAssertFalse(firstTool.isComplete)
        guard case .standaloneTool(_, let secondTool) = grouper.items[1] else {
            return XCTFail("Expected second tool row")
        }
        XCTAssertEqual(secondTool.id, "tool-date")
        XCTAssertFalse(secondTool.isComplete)
        guard case .toolApprovalBatch(_, let approvals, let status) = grouper.items[2] else {
            return XCTFail("Expected a grouped approval block")
        }
        XCTAssertEqual(approvals.map(\.toolUseId), ["tool-pwd", "tool-date"])
        XCTAssertNil(status)
    }

    func testParallelToolApprovalsDoNotCompleteAlreadyRenderedBatchTools() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let sessionId = "session-123"
        let pwdCall = bashToolCall(id: "pwd-call", conversationId: conversationId, toolId: "tool-pwd", command: "pwd")
        let dateCall = bashToolCall(id: "date-call", conversationId: conversationId, toolId: "tool-date", command: "date")
        let pwdApproval = bashToolApproval(
            id: "pwd-approval",
            conversationId: conversationId,
            sessionId: sessionId,
            toolId: "tool-pwd",
            command: "pwd"
        )
        let dateApproval = bashToolApproval(
            id: "date-approval",
            conversationId: conversationId,
            sessionId: sessionId,
            toolId: "tool-date",
            command: "date"
        )

        grouper.update(events: [pwdCall, dateCall, pwdApproval, dateApproval])

        XCTAssertEqual(grouper.items.count, 3)
        guard case .standaloneTool(_, let firstTool) = grouper.items[0] else {
            return XCTFail("Expected first tool row")
        }
        XCTAssertEqual(firstTool.id, "tool-pwd")
        XCTAssertFalse(firstTool.isComplete)
        guard case .standaloneTool(_, let secondTool) = grouper.items[1] else {
            return XCTFail("Expected second tool row")
        }
        XCTAssertEqual(secondTool.id, "tool-date")
        XCTAssertFalse(secondTool.isComplete)
        guard case .toolApprovalBatch(_, let approvals, _) = grouper.items[2] else {
            return XCTFail("Expected a grouped approval block")
        }
        XCTAssertEqual(approvals.map(\.toolUseId), ["tool-pwd", "tool-date"])
    }

    func testParallelToolApprovalsStayBatchedAcrossInterleavedReadOnlyResult() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let sessionId = "session-123"

        grouper.update(events: interleavedReadOnlyApprovalEvents(conversationId: conversationId, sessionId: sessionId))

        XCTAssertEqual(grouper.items.count, 4)
        let standaloneTools = standaloneTools(in: grouper.items)
        XCTAssertEqual(standaloneTools.map(\.id), ["tool-git-log", "tool-ls"])
        XCTAssertTrue(standaloneTools.allSatisfy { !$0.isComplete })
        XCTAssertEqual(toolGroups(in: grouper.items).map { $0.map(\.id) }, [["tool-grep"]])
        XCTAssertTrue(toolGroups(in: grouper.items).flatMap { $0 }.allSatisfy(\.isComplete))
        XCTAssertEqual(toolApprovalBatches(in: grouper.items).map { $0.approvals.map(\.toolUseId) }, [["tool-git-log", "tool-ls"]])
        XCTAssertNil(toolApprovalBatches(in: grouper.items).first?.status)
    }

    func testPendingApprovalBatchesLaterSameToolCallsBeforeAnyResult() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let sessionId = "session-123"
        let firstCall = writeToolCall(
            id: "first-call",
            conversationId: conversationId,
            toolId: "tool-write-1",
            filePath: "/tmp/one.txt"
        )
        let firstApproval = writeToolApproval(
            id: "first-approval",
            conversationId: conversationId,
            sessionId: sessionId,
            toolId: "tool-write-1",
            filePath: "/tmp/one.txt"
        )
        let secondCall = writeToolCall(
            id: "second-call",
            conversationId: conversationId,
            toolId: "tool-write-2",
            filePath: "/tmp/two.txt"
        )
        let thirdCall = writeToolCall(
            id: "third-call",
            conversationId: conversationId,
            toolId: "tool-write-3",
            filePath: "/tmp/three.txt"
        )

        grouper.update(events: [firstCall, firstApproval, secondCall, thirdCall])

        XCTAssertEqual(grouper.items.count, 4)
        let tools = grouper.items.prefix(3).compactMap { item -> ToolEntry? in
            guard case .standaloneTool(_, let tool) = item else {
                return nil
            }
            return tool
        }
        XCTAssertEqual(tools.map(\.id), ["tool-write-1", "tool-write-2", "tool-write-3"])
        XCTAssertTrue(tools.allSatisfy { !$0.isComplete })
        guard case .toolApprovalBatch(_, let approvals, let status) = grouper.items[3] else {
            return XCTFail("Expected later Write calls to join the pending approval batch")
        }
        XCTAssertEqual(approvals.map(\.toolUseId), ["tool-write-1", "tool-write-2", "tool-write-3"])
        XCTAssertNil(status)
    }

    func testActualApprovalRowsUpdateSyntheticBatchEntriesWithoutDuplicatingPrompt() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let sessionId = "session-123"
        let firstCall = writeToolCall(
            id: "first-call",
            conversationId: conversationId,
            toolId: "tool-write-1",
            filePath: "/tmp/one.txt"
        )
        let firstApproval = writeToolApproval(
            id: "first-approval",
            conversationId: conversationId,
            sessionId: sessionId,
            toolId: "tool-write-1",
            filePath: "/tmp/one.txt",
            status: .approved
        )
        let secondCall = writeToolCall(
            id: "second-call",
            conversationId: conversationId,
            toolId: "tool-write-2",
            filePath: "/tmp/two.txt"
        )
        let firstResult = ConversationEventRecord(
            id: "first-result",
            conversationId: conversationId,
            type: "tool_result",
            toolId: "tool-write-1",
            toolOutput: "File created successfully"
        )
        let secondApproval = writeToolApproval(
            id: "second-approval",
            conversationId: conversationId,
            sessionId: sessionId,
            toolId: "tool-write-2",
            filePath: "/tmp/two.txt",
            status: .approved
        )

        grouper.update(events: [firstCall, firstApproval, secondCall, firstResult, secondApproval])

        XCTAssertEqual(grouper.items.count, 3)
        guard case .toolApprovalBatch(_, let approvals, let status) = grouper.items[2] else {
            return XCTFail("Expected the actual second approval row to update the existing batch")
        }
        XCTAssertEqual(approvals.map(\.toolUseId), ["tool-write-1", "tool-write-2"])
        XCTAssertEqual(status, .approved)
    }

    func testPendingApprovalDoesNotBatchDifferentToolCallWithoutItsOwnApproval() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let sessionId = "session-123"
        let bashCall = bashToolCall(id: "bash-call", conversationId: conversationId, toolId: "tool-bash", command: "pwd")
        let bashApproval = bashToolApproval(
            id: "bash-approval",
            conversationId: conversationId,
            sessionId: sessionId,
            toolId: "tool-bash",
            command: "pwd"
        )
        let writeCall = writeToolCall(
            id: "write-call",
            conversationId: conversationId,
            toolId: "tool-write",
            filePath: "/tmp/one.txt"
        )

        grouper.update(events: [bashCall, bashApproval, writeCall])

        XCTAssertEqual(grouper.items.count, 3)
        guard case .standaloneTool(_, let tool) = grouper.items[1] else {
            return XCTFail("Expected the later Write call to render as a tool row, not a synthetic approval")
        }
        XCTAssertEqual(tool.id, "tool-write")
        guard case .toolApproval = grouper.items[2] else {
            return XCTFail("Expected the Bash approval to stay separate below later activity")
        }
    }

    func testToolApprovalRowsDoNotBatchDifferentToolFamilies() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let sessionId = "session-123"
        let bashApproval = bashToolApproval(
            id: "bash-approval",
            conversationId: conversationId,
            sessionId: sessionId,
            toolId: "tool-bash",
            command: "pwd"
        )
        let writeApproval = writeToolApproval(
            id: "write-approval",
            conversationId: conversationId,
            sessionId: sessionId,
            toolId: "tool-write",
            filePath: "/tmp/one.txt"
        )

        grouper.update(events: [bashApproval, writeApproval])

        XCTAssertEqual(grouper.items.count, 2)
        guard case .toolApproval(_, let firstApproval, _) = grouper.items[0] else {
            return XCTFail("Expected the Bash approval to stay separate")
        }
        guard case .toolApproval(_, let secondApproval, _) = grouper.items[1] else {
            return XCTFail("Expected the Write approval to stay separate")
        }
        XCTAssertEqual(firstApproval.toolName, "Bash")
        XCTAssertEqual(secondApproval.toolName, "Write")
    }

    func testToolApprovalsSeparatedByResultDoNotRenderAsBatchBlock() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let sessionId = "session-123"
        let firstApproval = ConversationEventRecord(
            id: "first-approval",
            conversationId: conversationId,
            type: "tool_approval",
            content: sessionId,
            toolId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"pwd\"}"
        )
        let firstResult = ConversationEventRecord(
            id: "first-result",
            conversationId: conversationId,
            type: "tool_result",
            toolId: "tool-1",
            toolOutput: "/tmp"
        )
        let secondApproval = ConversationEventRecord(
            id: "second-approval",
            conversationId: conversationId,
            type: "tool_approval",
            content: sessionId,
            toolId: "tool-2",
            toolName: "Bash",
            toolInput: "{\"command\":\"date\"}"
        )

        grouper.update(events: [firstApproval, firstResult, secondApproval])

        XCTAssertEqual(grouper.items.count, 2)
        guard case .toolApproval = grouper.items[0] else {
            return XCTFail("Expected first approval to remain separate")
        }
        guard case .toolApproval = grouper.items[1] else {
            return XCTFail("Expected second approval to remain separate")
        }
    }
}

private func bashToolCall(
    id: String,
    conversationId: String,
    toolId: String,
    command: String
) -> ConversationEventRecord {
    ConversationEventRecord(
        id: id,
        conversationId: conversationId,
        type: "tool_call",
        toolId: toolId,
        toolName: "Bash",
        toolInput: "{\"command\":\"\(command)\"}"
    )
}

private func bashToolApproval(
    id: String,
    conversationId: String,
    sessionId: String,
    toolId: String,
    command: String,
    status: ToolApprovalStatus? = nil
) -> ConversationEventRecord {
    ConversationEventRecord(
        id: id,
        conversationId: conversationId,
        type: "tool_approval",
        content: sessionId,
        toolId: toolId,
        toolName: "Bash",
        toolInput: "{\"command\":\"\(command)\"}",
        toolApprovalStatus: status?.rawValue
    )
}

private func interleavedReadOnlyApprovalEvents(conversationId: String, sessionId: String) -> [ConversationEventRecord] {
    [
        bashToolCall(
            id: "first-call",
            conversationId: conversationId,
            toolId: "tool-git-log",
            command: "git log --oneline -5"
        ),
        bashToolApproval(
            id: "first-approval",
            conversationId: conversationId,
            sessionId: sessionId,
            toolId: "tool-git-log",
            command: "git log --oneline -5"
        ),
        grepToolCall(id: "grep-call", conversationId: conversationId, toolId: "tool-grep", pattern: "**/*.html"),
        toolResult(id: "grep-result", conversationId: conversationId, toolId: "tool-grep", output: "index.html"),
        bashToolCall(id: "second-call", conversationId: conversationId, toolId: "tool-ls", command: "ls images/"),
        bashToolApproval(
            id: "second-approval",
            conversationId: conversationId,
            sessionId: sessionId,
            toolId: "tool-ls",
            command: "ls images/"
        )
    ]
}

private func grepToolCall(
    id: String,
    conversationId: String,
    toolId: String,
    pattern: String
) -> ConversationEventRecord {
    ConversationEventRecord(
        id: id,
        conversationId: conversationId,
        type: "tool_call",
        toolId: toolId,
        toolName: "Grep",
        toolInput: #"{"pattern":"\#(pattern)"}"#
    )
}

private func toolResult(
    id: String,
    conversationId: String,
    toolId: String,
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

private func standaloneTools(in items: [ChatItem]) -> [ToolEntry] {
    items.compactMap { item in
        guard case .standaloneTool(_, let tool) = item else {
            return nil
        }
        return tool
    }
}

private func toolGroups(in items: [ChatItem]) -> [[ToolEntry]] {
    items.compactMap { item in
        guard case .toolGroup(_, let tools) = item else {
            return nil
        }
        return tools
    }
}

private func toolApprovalBatches(in items: [ChatItem]) -> [(approvals: [ToolApprovalRequest], status: ToolApprovalStatus?)] {
    items.compactMap { item in
        guard case .toolApprovalBatch(_, let approvals, let status) = item else {
            return nil
        }
        return (approvals, status)
    }
}

private func writeToolCall(
    id: String,
    conversationId: String,
    toolId: String,
    filePath: String
) -> ConversationEventRecord {
    ConversationEventRecord(
        id: id,
        conversationId: conversationId,
        type: "tool_call",
        toolId: toolId,
        toolName: "Write",
        toolInput: #"{"file_path":"\#(filePath)","content":"test\n"}"#
    )
}

private func writeToolApproval(
    id: String,
    conversationId: String,
    sessionId: String,
    toolId: String,
    filePath: String,
    status: ToolApprovalStatus? = nil
) -> ConversationEventRecord {
    ConversationEventRecord(
        id: id,
        conversationId: conversationId,
        type: "tool_approval",
        content: sessionId,
        toolId: toolId,
        toolName: "Write",
        toolInput: #"{"file_path":"\#(filePath)","content":"test\n"}"#,
        toolApprovalStatus: status?.rawValue
    )
}

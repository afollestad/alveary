import XCTest

@testable import Alveary

extension ChatItemGrouperTests {
    func testToolApprovalClosesOpenToolGroupAndRendersStandaloneBlock() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let read = ConversationEventRecord(
            id: "read",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "r1",
            toolName: "Read",
            toolInput: "{\"file_path\":\"a.swift\"}"
        )
        let approval = ConversationEventRecord(
            id: "approval",
            conversationId: conversationId,
            type: "tool_approval",
            content: "session-123",
            toolId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test\"}"
        )

        grouper.update(events: [read, approval])

        XCTAssertEqual(grouper.items.count, 2)
        guard case .toolGroup(_, let tools) = grouper.items[0] else {
            return XCTFail("Expected the open Read group to close before approval")
        }
        XCTAssertEqual(tools.map(\.id), ["r1"])
        guard case .toolApproval(_, let request, let status) = grouper.items[1] else {
            return XCTFail("Expected a standalone tool approval block")
        }
        XCTAssertEqual(request.sessionId, "session-123")
        XCTAssertEqual(request.toolUseId, "tool-1")
        XCTAssertEqual(request.toolName, "Bash")
        XCTAssertNil(status)
    }

    func testToolApprovalCarriesPersistedResolutionStatus() {
        let grouper = ChatItemGrouper()
        let approval = ConversationEventRecord(
            id: "approval",
            conversationId: "conversation-1",
            type: "tool_approval",
            content: "session-123",
            toolId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test\"}",
            toolApprovalStatus: ToolApprovalStatus.approved.rawValue
        )

        grouper.update(events: [approval])

        guard case .toolApproval(_, _, let status) = grouper.items.first else {
            return XCTFail("Expected a standalone tool approval block")
        }
        XCTAssertEqual(status, .approved)
    }

    func testToolApprovalCarriesPersistedSessionApprovalStatus() {
        let grouper = ChatItemGrouper()
        let approval = ConversationEventRecord(
            id: "approval",
            conversationId: "conversation-1",
            type: "tool_approval",
            content: "session-123",
            toolId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"git add foo.swift\"}",
            toolApprovalStatus: ToolApprovalStatus.approvedForSessionGroup.rawValue
        )

        grouper.update(events: [approval])

        guard case .toolApproval(_, _, let status) = grouper.items.first else {
            return XCTFail("Expected a standalone tool approval block")
        }
        XCTAssertEqual(status, .approvedForSessionGroup)
    }

    func testToolApprovalCarriesPersistedSupersededStatus() {
        let grouper = ChatItemGrouper()
        let approval = ConversationEventRecord(
            id: "approval",
            conversationId: "conversation-1",
            type: "tool_approval",
            content: "session-123",
            toolId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test\"}",
            toolApprovalStatus: ToolApprovalStatus.superseded.rawValue
        )

        grouper.update(events: [approval])

        guard case .toolApproval(_, _, let status) = grouper.items.first else {
            return XCTFail("Expected a standalone tool approval block")
        }
        XCTAssertEqual(status, .superseded)
    }

    func testAskUserQuestionApprovalDoesNotRenderToolApprovalBlock() {
        let grouper = ChatItemGrouper()
        let promptCall = ConversationEventRecord(
            id: "prompt-call",
            conversationId: "conversation-1",
            type: "tool_call",
            toolId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
        )
        let approval = ConversationEventRecord(
            id: "approval",
            conversationId: "conversation-1",
            type: "tool_approval",
            content: "session-123",
            toolId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
        )

        grouper.update(events: [promptCall, approval])

        XCTAssertEqual(grouper.items.count, 1)
        guard case .promptBlock(_, let prompt) = grouper.items.first else {
            return XCTFail("Expected only the prompt block")
        }
        XCTAssertEqual(prompt.id, "prompt-1")
        XCTAssertNil(prompt.submittedSummary)
    }

    func testToolApprovalMarksEarlierPendingStandaloneToolComplete() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let write = ConversationEventRecord(
            id: "write",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "write-1",
            toolName: "Write",
            toolInput: #"{"file_path":"plan.md"}"#
        )
        let approval = ConversationEventRecord(
            id: "approval",
            conversationId: conversationId,
            type: "tool_approval",
            content: "session-123",
            toolId: "tool-exit",
            toolName: "ExitPlanMode",
            toolInput: "{}"
        )

        grouper.update(events: [write, approval])

        XCTAssertEqual(grouper.items.count, 2)
        guard case .standaloneTool(_, let tool) = grouper.items[0] else {
            return XCTFail("Expected the write tool row to remain visible")
        }
        XCTAssertEqual(tool.id, "write-1")
        XCTAssertTrue(tool.isComplete)
        XCTAssertFalse(tool.isError)
        guard case .toolApproval(_, let request, _) = grouper.items[1] else {
            return XCTFail("Expected the later approval row")
        }
        XCTAssertEqual(request.toolUseId, "tool-exit")
    }
}

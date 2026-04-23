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
}

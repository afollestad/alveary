import XCTest

@testable import Alveary

extension ChatItemGrouperTests {
    func testEnterPlanModeToolRendersCenteredNoteOnSuccess() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let toolCall = ConversationEventRecord(
            id: "enter-plan-call",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "tool-1",
            toolName: "EnterPlanMode",
            toolInput: "{}"
        )
        let toolResult = ConversationEventRecord(
            id: "enter-plan-result",
            conversationId: conversationId,
            type: "tool_result",
            toolId: "tool-1",
            toolOutput: ""
        )

        grouper.update(events: [toolCall, toolResult])

        XCTAssertEqual(grouper.items, [.centeredNote(id: "note-tool-1", kind: .enteredPlanMode)])
    }

    func testExitPlanModeToolRendersCenteredNoteOnSuccess() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let toolCall = ConversationEventRecord(
            id: "exit-plan-call",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "tool-1",
            toolName: "ExitPlanMode",
            toolInput: "{}"
        )
        let toolResult = ConversationEventRecord(
            id: "exit-plan-result",
            conversationId: conversationId,
            type: "tool_result",
            toolId: "tool-1",
            toolOutput: ""
        )

        grouper.update(events: [toolCall, toolResult])

        XCTAssertEqual(grouper.items, [.centeredNote(id: "note-tool-1", kind: .exitedPlanMode)])
    }

    func testDeniedExitPlanModeRendersCenteredStayingNote() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let approval = ConversationEventRecord(
            id: "approval",
            conversationId: conversationId,
            type: "tool_approval",
            content: "session-123",
            toolId: "tool-1",
            toolName: "ExitPlanMode",
            toolInput: "{}",
            toolApprovalStatus: ToolApprovalStatus.denied.rawValue
        )
        let toolCall = ConversationEventRecord(
            id: "exit-plan-call",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "tool-1",
            toolName: "ExitPlanMode",
            toolInput: "{}"
        )
        let toolResult = ConversationEventRecord(
            id: "exit-plan-result",
            conversationId: conversationId,
            type: "tool_result",
            toolId: "tool-1",
            toolOutput: "User denied ExitPlanMode.",
            isError: true
        )

        grouper.update(events: [approval, toolCall, toolResult])

        XCTAssertEqual(grouper.items.count, 2)
        guard case .toolApproval(_, _, let status) = grouper.items[0] else {
            return XCTFail("Expected the resolved tool approval block to remain in transcript history")
        }
        XCTAssertEqual(status, .denied)
        XCTAssertEqual(grouper.items[1], .centeredNote(id: "note-tool-1", kind: .stayingInPlanMode))
    }

    func testRealExitPlanModeFailureStillFallsBackToStandaloneToolRow() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let toolCall = ConversationEventRecord(
            id: "exit-plan-call",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "tool-1",
            toolName: "ExitPlanMode",
            toolInput: "{}"
        )
        let toolResult = ConversationEventRecord(
            id: "exit-plan-result",
            conversationId: conversationId,
            type: "tool_result",
            toolId: "tool-1",
            toolOutput: "You are not in plan mode.",
            isError: true
        )

        grouper.update(events: [toolCall, toolResult])

        XCTAssertEqual(grouper.items.count, 1)
        guard case .standaloneTool(_, let tool) = grouper.items[0] else {
            return XCTFail("Expected failed plan-mode tool to fall back to a standalone tool row")
        }
        XCTAssertEqual(tool.name, "ExitPlanMode")
        XCTAssertTrue(tool.isError)
        XCTAssertEqual(tool.output, "You are not in plan mode.")
    }

    func testPlanModeToolFailureClosesOpenGroupBeforeFallbackRow() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let read = ConversationEventRecord(
            id: "read-call",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "read-1",
            toolName: "Read",
            toolInput: #"{"file_path":"README.md"}"#
        )
        let planCall = ConversationEventRecord(
            id: "exit-plan-call",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "tool-1",
            toolName: "ExitPlanMode",
            toolInput: "{}"
        )
        let planResult = ConversationEventRecord(
            id: "exit-plan-result",
            conversationId: conversationId,
            type: "tool_result",
            toolId: "tool-1",
            toolOutput: "You are not in plan mode.",
            isError: true
        )

        grouper.update(events: [read, planCall, planResult])

        XCTAssertEqual(grouper.items.count, 2)
        guard case .toolGroup(_, let tools) = grouper.items[0] else {
            return XCTFail("Expected the open group to close before the failed plan-mode row")
        }
        XCTAssertEqual(tools.map(\.id), ["read-1"])
        guard case .standaloneTool(_, let tool) = grouper.items[1] else {
            return XCTFail("Expected a standalone fallback row for the failed plan-mode tool")
        }
        XCTAssertEqual(tool.name, "ExitPlanMode")
        XCTAssertTrue(tool.isError)
    }

    func testResetInFlightStateClearsPendingPlanModeNoteTracking() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let toolCall = ConversationEventRecord(
            id: "enter-plan-call",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "tool-1",
            toolName: "EnterPlanMode",
            toolInput: "{}"
        )

        grouper.update(events: [toolCall])
        grouper.resetInFlightStateForNewSession()

        XCTAssertTrue(grouper.centeredNoteToolKinds.isEmpty)
    }

    func testContextCompactionStartRendersCenteredNote() {
        let grouper = ChatItemGrouper()
        let event = ConversationEventRecord(
            id: "compact-start",
            conversationId: "conversation-1",
            type: ConversationContextCompaction.startedType,
            toolId: "compact-1"
        )

        grouper.update(events: [event])

        XCTAssertEqual(grouper.items, [
            .centeredNote(id: "context-compaction-compact-1", kind: .contextCompactionStarted)
        ])
    }

    func testContextCompactionTerminalEventReplacesStartNote() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let start = ConversationEventRecord(
            id: "compact-start",
            conversationId: conversationId,
            type: ConversationContextCompaction.startedType,
            toolId: "compact-1"
        )
        let completed = ConversationEventRecord(
            id: "compact-completed",
            conversationId: conversationId,
            type: ConversationContextCompaction.completedType,
            toolId: "compact-1"
        )

        grouper.update(events: [start, completed])

        XCTAssertEqual(grouper.items, [
            .centeredNote(id: "context-compaction-compact-1", kind: .contextCompactionCompleted)
        ])
    }

    func testContextCompactionClosesOpenGroupBeforeCenteredNote() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let read = ConversationEventRecord(
            id: "read-call",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "read-1",
            toolName: "Read",
            toolInput: #"{"file_path":"README.md"}"#
        )
        let compaction = ConversationEventRecord(
            id: "compact-start",
            conversationId: conversationId,
            type: ConversationContextCompaction.startedType,
            toolId: "compact-1"
        )

        grouper.update(events: [read, compaction])

        XCTAssertEqual(grouper.items.count, 2)
        guard case .toolGroup(_, let tools) = grouper.items[0] else {
            return XCTFail("Expected the pending tool group to close before compaction")
        }
        XCTAssertEqual(tools.map(\.id), ["read-1"])
        XCTAssertEqual(grouper.items[1], .centeredNote(id: "context-compaction-compact-1", kind: .contextCompactionStarted))
    }

    func testContextCompactionFailureReplacesStartNote() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let start = ConversationEventRecord(
            id: "compact-start",
            conversationId: conversationId,
            type: ConversationContextCompaction.startedType,
            toolId: "compact-1"
        )
        let failed = ConversationEventRecord(
            id: "compact-failed",
            conversationId: conversationId,
            type: ConversationContextCompaction.failedType,
            content: "Compact hook failed",
            toolId: "compact-1",
            isError: true
        )

        grouper.update(events: [start, failed])

        XCTAssertEqual(grouper.items, [
            .centeredNote(id: "context-compaction-compact-1", kind: .contextCompactionFailed)
        ])
    }
}

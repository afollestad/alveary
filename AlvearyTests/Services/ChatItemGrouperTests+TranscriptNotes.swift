import XCTest

@testable import Alveary

extension ChatItemGrouperTests {
    func testEnterPlanModeToolRendersTranscriptNoteOnSuccess() {
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

        XCTAssertEqual(grouper.items, [.transcriptNote(id: "note-tool-1", kind: .enteredPlanMode)])
    }

    func testExitPlanModeToolRendersTranscriptNoteOnSuccess() {
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

        XCTAssertEqual(grouper.items, [.transcriptNote(id: "note-tool-1", kind: .exitedPlanMode)])
    }

    func testDeniedExitPlanModeRendersStayingTranscriptNote() {
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
        XCTAssertEqual(grouper.items[1], .transcriptNote(id: "note-tool-1", kind: .stayingInPlanMode))
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

        XCTAssertTrue(grouper.transcriptNoteToolKinds.isEmpty)
    }

    func testContextCompactionStartRendersTranscriptNote() {
        let grouper = ChatItemGrouper()
        let event = ConversationEventRecord(
            id: "compact-start",
            conversationId: "conversation-1",
            type: ConversationContextCompaction.startedType,
            toolId: "compact-1"
        )

        grouper.update(events: [event])

        XCTAssertEqual(grouper.items, [
            .transcriptNote(id: "context-compaction-compact-1", kind: .contextCompactionStarted)
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
            .transcriptNote(id: "context-compaction-compact-1", kind: .contextCompactionCompleted)
        ])
    }

    func testContextCompactionClosesOpenGroupBeforeTranscriptNote() {
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
        XCTAssertEqual(grouper.items[1], .transcriptNote(id: "context-compaction-compact-1", kind: .contextCompactionStarted))
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
            .transcriptNote(id: "context-compaction-compact-1", kind: .contextCompactionFailed)
        ])
    }

    func testDuplicateAssistantThenErrorPrefersErrorBanner() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"

        grouper.update(events: [
            messageRecord(id: "user", conversationId: conversationId, role: "user", content: "Try bad model"),
            messageRecord(id: "assistant", conversationId: conversationId, role: "assistant", content: "Selected model is unavailable."),
            errorRecord(id: "error", conversationId: conversationId, message: "Selected model is unavailable.")
        ])

        XCTAssertEqual(grouper.items, [
            .userMessage(id: "user", text: "Try bad model"),
            .error(id: "error", message: "Selected model is unavailable.")
        ])
    }

    func testDuplicateErrorThenAssistantPrefersExistingErrorBanner() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"

        grouper.update(events: [
            messageRecord(id: "user", conversationId: conversationId, role: "user", content: "Try bad model"),
            errorRecord(id: "error", conversationId: conversationId, message: "Selected model is unavailable."),
            messageRecord(id: "assistant", conversationId: conversationId, role: "assistant", content: "Selected model is unavailable.")
        ])

        XCTAssertEqual(grouper.items, [
            .userMessage(id: "user", text: "Try bad model"),
            .error(id: "error", message: "Selected model is unavailable.")
        ])
    }

    func testDuplicateErrorRowsKeepFirstErrorIdentity() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"

        grouper.update(events: [
            messageRecord(id: "user", conversationId: conversationId, role: "user", content: "Try bad model"),
            errorRecord(id: "error-1", conversationId: conversationId, message: "Selected model is unavailable."),
            errorRecord(id: "error-2", conversationId: conversationId, message: " Selected   model is unavailable. ")
        ])

        XCTAssertEqual(grouper.items, [
            .userMessage(id: "user", text: "Try bad model"),
            .error(id: "error-1", message: "Selected model is unavailable.")
        ])
    }

    func testNonDuplicateAssistantAndErrorBothRemainVisible() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"

        grouper.update(events: [
            messageRecord(id: "user", conversationId: conversationId, role: "user", content: "Try bad model"),
            messageRecord(id: "assistant", conversationId: conversationId, role: "assistant", content: "I could not start."),
            errorRecord(id: "error", conversationId: conversationId, message: "Provider authentication failed.")
        ])

        XCTAssertEqual(grouper.items, [
            .userMessage(id: "user", text: "Try bad model"),
            .assistantMessage(id: "assistant", text: "I could not start."),
            .error(id: "error", message: "Provider authentication failed.")
        ])
    }

    func testDuplicateErrorTextDoesNotSuppressAcrossTurns() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"

        grouper.update(events: [
            messageRecord(id: "user-1", conversationId: conversationId, role: "user", content: "First turn"),
            messageRecord(id: "assistant", conversationId: conversationId, role: "assistant", content: "Selected model is unavailable."),
            messageRecord(id: "user-2", conversationId: conversationId, role: "user", content: "Second turn"),
            errorRecord(id: "error", conversationId: conversationId, message: "Selected model is unavailable.")
        ])

        XCTAssertEqual(grouper.items, [
            .userMessage(id: "user-1", text: "First turn"),
            .assistantMessage(id: "assistant", text: "Selected model is unavailable."),
            .userMessage(id: "user-2", text: "Second turn"),
            .error(id: "error", message: "Selected model is unavailable.")
        ])
    }

    func testDuplicateErrorSuppressionPreservesIncompleteTaskListPinning() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"

        grouper.update(events: [
            messageRecord(id: "user", conversationId: conversationId, role: "user", content: "Try bad model"),
            todoWriteRecord(id: "todo", conversationId: conversationId),
            messageRecord(id: "assistant", conversationId: conversationId, role: "assistant", content: "Selected model is unavailable."),
            errorRecord(id: "error", conversationId: conversationId, message: "Selected model is unavailable.")
        ])

        XCTAssertEqual(grouper.items.count, 3)
        XCTAssertEqual(grouper.items[0], .userMessage(id: "user", text: "Try bad model"))
        XCTAssertEqual(grouper.items[1], .error(id: "error", message: "Selected model is unavailable."))
        guard case .taskListBlock(_, let tasks) = grouper.items[2] else {
            return XCTFail("Expected the incomplete task list to remain pinned after the error")
        }
        XCTAssertEqual(tasks.first?.content, "Check model")
        XCTAssertEqual(tasks.first?.status, .inProgress)
    }

    private func messageRecord(
        id: String,
        conversationId: String,
        role: String,
        content: String
    ) -> ConversationEventRecord {
        ConversationEventRecord(
            id: id,
            conversationId: conversationId,
            type: "message",
            role: role,
            content: content
        )
    }

    private func errorRecord(
        id: String,
        conversationId: String,
        message: String
    ) -> ConversationEventRecord {
        ConversationEventRecord(
            id: id,
            conversationId: conversationId,
            type: "error",
            content: message
        )
    }

    private func todoWriteRecord(id: String, conversationId: String) -> ConversationEventRecord {
        ConversationEventRecord(
            id: id,
            conversationId: conversationId,
            type: "tool_call",
            toolId: id,
            toolName: "TodoWrite",
            toolInput: #"{ "todos": [{ "content": "Check model", "status": "in_progress", "activeForm": "Checking model" }] }"#
        )
    }
}

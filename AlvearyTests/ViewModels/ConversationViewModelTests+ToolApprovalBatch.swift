import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testSupersededApprovalIsNotSubmittedAsRelatedBatchApproval() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let conversation = try fixture.dbConversation()
        let oldApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"date\"}"
        )
        let newApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-2",
            toolName: "Bash",
            toolInput: "{\"command\":\"pwd\"}"
        )
        let oldApprovalRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: oldApproval.sessionId,
            toolId: oldApproval.toolUseId,
            toolName: oldApproval.toolName,
            toolInput: oldApproval.toolInput,
            toolApprovalStatus: ToolApprovalStatus.superseded.rawValue,
            timestamp: Date(timeIntervalSince1970: 1),
            conversation: conversation
        )
        let newApprovalRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: newApproval.sessionId,
            toolId: newApproval.toolUseId,
            toolName: newApproval.toolName,
            toolInput: newApproval.toolInput,
            timestamp: Date(timeIntervalSince1970: 2),
            conversation: conversation
        )
        fixture.context.insert(oldApprovalRecord)
        fixture.context.insert(newApprovalRecord)
        try fixture.context.save()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: newApproval, status: .pending)

        try await fixture.viewModel.approveToolUse(toolUseId: newApproval.toolUseId)

        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertTrue(calls.first?.additionalApprovals.isEmpty == true)
        XCTAssertEqual(oldApprovalRecord.toolApprovalStatus, ToolApprovalStatus.superseded.rawValue)
    }

    func testRelatedBatchApprovalStatusIsNotPersistedWhenApprovalFails() async throws {
        let fixture = try ConversationViewModelTestFixture(
            approvalError: .approvalFailed,
            initialAgentIsRunning: false
        )
        let conversation = try fixture.dbConversation()
        let oldApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"date\"}"
        )
        let newApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-2",
            toolName: "Bash",
            toolInput: "{\"command\":\"pwd\"}"
        )
        let oldApprovalRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: oldApproval.sessionId,
            toolId: oldApproval.toolUseId,
            toolName: oldApproval.toolName,
            toolInput: oldApproval.toolInput,
            timestamp: Date(timeIntervalSince1970: 1),
            conversation: conversation
        )
        let newApprovalRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: newApproval.sessionId,
            toolId: newApproval.toolUseId,
            toolName: newApproval.toolName,
            toolInput: newApproval.toolInput,
            timestamp: Date(timeIntervalSince1970: 2),
            conversation: conversation
        )
        fixture.context.insert(oldApprovalRecord)
        fixture.context.insert(newApprovalRecord)
        try fixture.context.save()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: newApproval, status: .pending)

        do {
            try await fixture.viewModel.approveToolUse(toolUseId: newApproval.toolUseId)
            XCTFail("Expected approval resume to fail")
        } catch {}

        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(calls.first?.additionalApprovals, [oldApproval])
        XCTAssertNil(oldApprovalRecord.toolApprovalStatus)
        XCTAssertNil(newApprovalRecord.toolApprovalStatus)
    }

    func testRelatedBatchApprovalsDoNotIncludeDifferentToolFamilyRows() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        let conversation = try fixture.dbConversation()
        let writeApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-write",
            toolName: "Write",
            toolInput: #"{"file_path":"/tmp/one.txt","content":"one\n"}"#
        )
        let bashApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-bash",
            toolName: "Bash",
            toolInput: #"{"command":"pwd"}"#
        )
        fixture.context.insert(toolApprovalRecord(
            conversation: conversation,
            request: writeApproval,
            timestamp: 1
        ))
        fixture.context.insert(toolApprovalRecord(
            conversation: conversation,
            request: bashApproval,
            timestamp: 2
        ))
        try fixture.context.save()
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: bashApproval, status: .pending)

        try await fixture.viewModel.approveToolUse(toolUseId: bashApproval.toolUseId)

        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertTrue(calls.first?.additionalApprovals.isEmpty == true)
    }

    func testRelatedBatchApprovalsDoNotCrossMessageBoundary() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        let conversation = try fixture.dbConversation()
        let oldApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Write",
            toolInput: #"{"file_path":"/tmp/old.txt","content":"old\n"}"#
        )
        let newApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-2",
            toolName: "Write",
            toolInput: #"{"file_path":"/tmp/new.txt","content":"new\n"}"#
        )
        fixture.context.insert(toolApprovalRecord(
            conversation: conversation,
            request: oldApproval,
            timestamp: 1
        ))
        fixture.context.insert(ConversationEventRecord(
            conversationId: conversation.id,
            type: "message",
            role: "assistant",
            content: "Done with the previous request.",
            timestamp: Date(timeIntervalSince1970: 2),
            conversation: conversation
        ))
        fixture.context.insert(toolApprovalRecord(
            conversation: conversation,
            request: newApproval,
            timestamp: 3
        ))
        try fixture.context.save()
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: newApproval, status: .pending)

        try await fixture.viewModel.approveToolUse(toolUseId: newApproval.toolUseId)

        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertTrue(calls.first?.additionalApprovals.isEmpty == true)
    }

    func testRelatedBatchApprovalsIncludeSameToolCallsThatHaveNotReachedHookYet() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        let firstApproval = writeApprovalRequest(toolUseId: "tool-1", filePath: "/tmp/one.txt", content: "one")
        let secondApproval = writeApprovalRequest(toolUseId: "tool-2", filePath: "/tmp/two.txt", content: "two")
        let thirdApproval = writeApprovalRequest(toolUseId: "tool-3", filePath: "/tmp/three.txt", content: "three")
        try insertToolApprovalBatchEvents(
            fixture: fixture,
            approval: firstApproval,
            siblingToolCalls: [secondApproval, thirdApproval]
        )
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: firstApproval, status: .pending)

        try await fixture.viewModel.approveToolUse(toolUseId: firstApproval.toolUseId)

        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(calls.first?.additionalApprovals, [secondApproval, thirdApproval])
    }

    func testRelatedBatchApprovalsIncludeUnresolvedApprovalRowsAfterSelectedApproval() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        let conversation = try fixture.dbConversation()
        let firstApproval = writeApprovalRequest(toolUseId: "tool-1", filePath: "/tmp/one.txt", content: "one")
        let selectedApproval = writeApprovalRequest(toolUseId: "tool-2", filePath: "/tmp/two.txt", content: "two")
        let laterApproval = writeApprovalRequest(toolUseId: "tool-3", filePath: "/tmp/three.txt", content: "three")
        fixture.context.insert(toolApprovalRecord(
            conversation: conversation,
            request: firstApproval,
            timestamp: 1
        ))
        fixture.context.insert(toolApprovalRecord(
            conversation: conversation,
            request: selectedApproval,
            timestamp: 2
        ))
        fixture.context.insert(toolApprovalRecord(
            conversation: conversation,
            request: laterApproval,
            timestamp: 3
        ))
        try fixture.context.save()
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: selectedApproval, status: .pending)

        try await fixture.viewModel.approveToolUse(toolUseId: selectedApproval.toolUseId)

        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(calls.first?.additionalApprovals, [firstApproval, laterApproval])
        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertEqual(firstApprovalStatus(in: conversation, toolUseId: firstApproval.toolUseId), ToolApprovalStatus.approved.rawValue)
        XCTAssertEqual(firstApprovalStatus(in: conversation, toolUseId: selectedApproval.toolUseId), ToolApprovalStatus.approved.rawValue)
        XCTAssertEqual(firstApprovalStatus(in: conversation, toolUseId: laterApproval.toolUseId), ToolApprovalStatus.approved.rawValue)
    }

    func testRelatedBatchApprovalsDoNotIncludeNonDeferredSiblingToolCallsForCurrentMode() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        let conversation = try fixture.dbConversation()
        let thread = try fixture.dbThread()
        thread.permissionMode = "acceptEdits"
        let bashApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: #"{"command":"pwd"}"#
        )
        let writeToolInput = #"{"file_path":"/tmp/one.txt","content":"one\n"}"#
        let bashApprovalRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: bashApproval.sessionId,
            toolId: bashApproval.toolUseId,
            toolName: bashApproval.toolName,
            toolInput: bashApproval.toolInput,
            timestamp: Date(timeIntervalSince1970: 1),
            conversation: conversation
        )
        let writeToolCallRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_call",
            toolId: "tool-2",
            toolName: "Write",
            toolInput: writeToolInput,
            timestamp: Date(timeIntervalSince1970: 2),
            conversation: conversation
        )
        fixture.context.insert(bashApprovalRecord)
        fixture.context.insert(writeToolCallRecord)
        try fixture.context.save()
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: bashApproval, status: .pending)

        try await fixture.viewModel.approveToolUse(toolUseId: bashApproval.toolUseId)

        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertTrue(calls.first?.additionalApprovals.isEmpty == true)
    }
}

@MainActor
private func insertToolApprovalBatchEvents(
    fixture: ConversationViewModelTestFixture,
    approval: ToolApprovalRequest,
    siblingToolCalls: [ToolApprovalRequest]
) throws {
    let conversation = try fixture.dbConversation()
    fixture.context.insert(toolCallRecord(
        conversation: conversation,
        request: approval,
        timestamp: 1
    ))
    fixture.context.insert(toolApprovalRecord(
        conversation: conversation,
        request: approval,
        timestamp: 2
    ))
    for (offset, request) in siblingToolCalls.enumerated() {
        fixture.context.insert(toolCallRecord(
            conversation: conversation,
            request: request,
            timestamp: TimeInterval(offset + 3)
        ))
    }
    try fixture.context.save()
}

private func writeApprovalRequest(
    toolUseId: String,
    filePath: String,
    content: String
) -> ToolApprovalRequest {
    ToolApprovalRequest(
        sessionId: "session-123",
        toolUseId: toolUseId,
        toolName: "Write",
        toolInput: #"{"file_path":"\#(filePath)","content":"\#(content)\n"}"#
    )
}

private func toolCallRecord(
    conversation: Conversation,
    request: ToolApprovalRequest,
    timestamp: TimeInterval
) -> ConversationEventRecord {
    ConversationEventRecord(
        conversationId: conversation.id,
        type: "tool_call",
        toolId: request.toolUseId,
        toolName: request.toolName,
        toolInput: request.toolInput,
        timestamp: Date(timeIntervalSince1970: timestamp),
        conversation: conversation
    )
}

private func toolApprovalRecord(
    conversation: Conversation,
    request: ToolApprovalRequest,
    timestamp: TimeInterval
) -> ConversationEventRecord {
    ConversationEventRecord(
        conversationId: conversation.id,
        type: "tool_approval",
        content: request.sessionId,
        toolId: request.toolUseId,
        toolName: request.toolName,
        toolInput: request.toolInput,
        timestamp: Date(timeIntervalSince1970: timestamp),
        conversation: conversation
    )
}

private func firstApprovalStatus(in conversation: Conversation, toolUseId: String) -> String? {
    conversation.events.first {
        $0.type == "tool_approval" && $0.toolId == toolUseId
    }?.toolApprovalStatus
}

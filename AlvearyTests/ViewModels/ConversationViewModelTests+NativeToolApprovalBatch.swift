import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testRelatedBatchApprovalsIncludeEscapingReadToolCallsThatHaveNotReachedHookYet() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        let firstApproval = nativeReadApprovalRequest(toolUseId: "tool-1", filePath: "/tmp/outside/one.txt")
        let secondApproval = nativeReadApprovalRequest(toolUseId: "tool-2", filePath: "/tmp/outside/two.txt")
        try insertNativeToolApprovalBatchEvents(
            fixture: fixture,
            approval: firstApproval,
            siblingToolCalls: [secondApproval]
        )
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: firstApproval, status: .pending)

        try await fixture.viewModel.approveToolUse(toolUseId: firstApproval.toolUseId)

        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(calls.first?.additionalApprovals, [secondApproval])
    }

    func testRelatedBatchApprovalsDoNotIncludeInProjectReadToolCallsThatHaveNotReachedHookYet() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        let firstApproval = nativeReadApprovalRequest(toolUseId: "tool-1", filePath: "/tmp/outside/one.txt")
        let secondApproval = nativeReadApprovalRequest(toolUseId: "tool-2", filePath: "Sources/App.swift")
        try insertNativeToolApprovalBatchEvents(
            fixture: fixture,
            approval: firstApproval,
            siblingToolCalls: [secondApproval]
        )
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: firstApproval, status: .pending)

        try await fixture.viewModel.approveToolUse(toolUseId: firstApproval.toolUseId)

        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertTrue(calls.first?.additionalApprovals.isEmpty == true)
    }
}

@MainActor
private func insertNativeToolApprovalBatchEvents(
    fixture: ConversationViewModelTestFixture,
    approval: ToolApprovalRequest,
    siblingToolCalls: [ToolApprovalRequest]
) throws {
    let conversation = try fixture.dbConversation()
    fixture.context.insert(nativeToolCallRecord(
        conversation: conversation,
        request: approval,
        timestamp: 1
    ))
    fixture.context.insert(nativeToolApprovalRecord(
        conversation: conversation,
        request: approval,
        timestamp: 2
    ))
    for (offset, request) in siblingToolCalls.enumerated() {
        fixture.context.insert(nativeToolCallRecord(
            conversation: conversation,
            request: request,
            timestamp: TimeInterval(offset + 3)
        ))
    }
    try fixture.context.save()
}

private func nativeReadApprovalRequest(toolUseId: String, filePath: String) -> ToolApprovalRequest {
    ToolApprovalRequest(
        sessionId: "session-123",
        toolUseId: toolUseId,
        toolName: "Read",
        toolInput: #"{"file_path":"\#(filePath)"}"#
    )
}

private func nativeToolCallRecord(
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

private func nativeToolApprovalRecord(
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

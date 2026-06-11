import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testApprovingOlderUnrelatedApprovalRehydratesRemainingApproval() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let conversation = try fixture.dbConversation()
        let readApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-read",
            toolName: "Read",
            toolInput: "{\"file_path\":\"Sources/Old.swift\"}"
        )
        let bashApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-bash",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test\"}"
        )
        let readApprovalRecord = replacementToolApprovalRecord(
            conversation: conversation,
            request: readApproval,
            timestamp: 1
        )
        let bashApprovalRecord = replacementToolApprovalRecord(
            conversation: conversation,
            request: bashApproval,
            timestamp: 2
        )
        fixture.context.insert(readApprovalRecord)
        fixture.context.insert(bashApprovalRecord)
        try fixture.context.save()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: bashApproval, status: .pending)

        try await fixture.viewModel.approveToolUse(toolUseId: readApproval.toolUseId)

        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.approval, readApproval)
        XCTAssertTrue(calls.first?.additionalApprovals.isEmpty == true)
        XCTAssertEqual(readApprovalRecord.toolApprovalStatus, ToolApprovalStatus.approved.rawValue)
        XCTAssertNil(bashApprovalRecord.toolApprovalStatus)
        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval, PendingToolApproval(request: bashApproval, status: .pending))
    }

    func testApprovingClickedApprovalUsesSessionAndToolUseId() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let conversation = try fixture.dbConversation()
        let oldApproval = ToolApprovalRequest(
            sessionId: "session-old",
            toolUseId: "shared-tool",
            toolName: "Read",
            toolInput: "{\"file_path\":\"Sources/Old.swift\"}"
        )
        let newApproval = ToolApprovalRequest(
            sessionId: "session-new",
            toolUseId: "shared-tool",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test\"}"
        )
        let oldApprovalRecord = replacementToolApprovalRecord(
            conversation: conversation,
            request: oldApproval,
            timestamp: 1
        )
        let newApprovalRecord = replacementToolApprovalRecord(
            conversation: conversation,
            request: newApproval,
            timestamp: 2
        )
        fixture.context.insert(oldApprovalRecord)
        fixture.context.insert(newApprovalRecord)
        try fixture.context.save()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: newApproval, status: .pending)

        try await fixture.viewModel.approveToolUse(oldApproval)

        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.approval, oldApproval)
        XCTAssertEqual(oldApprovalRecord.toolApprovalStatus, ToolApprovalStatus.approved.rawValue)
        XCTAssertNil(newApprovalRecord.toolApprovalStatus)
        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval, PendingToolApproval(request: newApproval, status: .pending))
    }
}

private func replacementToolApprovalRecord(
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

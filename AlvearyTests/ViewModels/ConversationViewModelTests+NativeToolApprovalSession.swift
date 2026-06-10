import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testApproveNativeReadToolUseForSessionRecordsExactPathApproval() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Read",
            toolInput: #"{"file_path":"/tmp/outside/settings.json"}"#
        )
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.approveToolUseForSession(
            toolUseId: "tool-1",
            scope: .exact
        )

        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(
            calls.first?.sessionApproval,
            AgentSessionApprovalGrant(
                providerId: "claude",
                conversationId: fixture.conversation.id,
                sessionId: "session-123",
                matchKind: .filePathExact,
                matchValue: "/tmp/outside/settings.json"
            )
        )
    }

    func testToolApprovalSelectionNormalizesUnsupportedStoredSessionSelectionToOnce() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Grep",
            toolInput: #"{"pattern":"token","path":"/tmp/outside"}"#
        )
        await fixture.agentsManager.recordToolApprovalSelection(
            .sessionGroup,
            providerId: "claude",
            conversationId: fixture.conversation.id,
            sessionId: approval.sessionId
        )

        let selection = await fixture.viewModel.toolApprovalSelection(for: approval)
        let persistedSelection = await fixture.agentsManager.toolApprovalSelection(
            providerId: "claude",
            conversationId: fixture.conversation.id,
            sessionId: approval.sessionId
        )

        XCTAssertEqual(selection, .once)
        XCTAssertEqual(persistedSelection, .once)
    }
}

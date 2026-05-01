import XCTest

@testable import Alveary

extension ConversationViewModelTests {
    func testDenyToolUseDuringActiveTurnEndsTurnAfterLiveHookDecision() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test\"}"
        )
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
        await fixture.agentsManager.enableSubscription()

        try await fixture.viewModel.denyToolUse(toolUseId: "tool-1")

        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertFalse(fixture.viewModel.state.turnState.isActive)
        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.decision, .deny)
        let subscribeCalls = await fixture.agentsManager.subscribeCalls()
        XCTAssertEqual(subscribeCalls, 0)
    }
}

import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testApproveExitPlanModeRoutesAllowDecisionForClaude() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false, providerId: "claude")
        let approval = exitPlanModeApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.approveExitPlanMode(toolUseId: approval.toolUseId)

        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.decision, .allow)
        XCTAssertEqual(calls.first?.approval, approval)
        XCTAssertEqual(calls.first?.config.providerId, "claude")
        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.status, .approving)
    }

    func testDismissExitPlanModeRoutesDenyDecisionForCodex() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false, providerId: "codex")
        let approval = exitPlanModeApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.denyExitPlanMode(toolUseId: approval.toolUseId)

        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.decision, .deny)
        XCTAssertEqual(calls.first?.approval, approval)
        XCTAssertEqual(calls.first?.config.providerId, "codex")
        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertFalse(fixture.viewModel.state.turnState.isActive)
        XCTAssertNil(fixture.viewModel.state.pendingExitPlanModeFollowUp)
    }

    func testCustomDenyFollowUpWaitsForApprovalClearThenSendsBeforeOlderQueuedMessages() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let conversation = try fixture.dbConversation()
        let approval = exitPlanModeApproval(toolUseId: "exit-plan-1")
        let approvalRecord = exitPlanModeApprovalRecord(conversation: conversation, approval: approval)
        fixture.context.insert(approvalRecord)
        try fixture.context.save()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
        fixture.viewModel.state.messageQueue.enqueue("Older queued message", stagedContext: "Queued context")
        fixture.viewModel.state.stagedContext = "Live staged context"

        try await fixture.viewModel.denyExitPlanMode(
            toolUseId: approval.toolUseId,
            followUp: "  Please revise the plan first.  "
        )

        try await waitUntil("custom plan follow-up sent before older queued messages") {
            await fixture.agentsManager.sentMessages() == ["Please revise the plan first."]
        }

        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertNil(fixture.viewModel.state.pendingExitPlanModeFollowUp)
        XCTAssertEqual(fixture.viewModel.state.messageQueue.pending.map(\.text), ["Older queued message"])
        XCTAssertEqual(fixture.viewModel.state.messageQueue.pending.first?.stagedContext, "Queued context")
        XCTAssertEqual(fixture.viewModel.state.stagedContext, "Live staged context")
        XCTAssertEqual(approvalRecord.toolApprovalStatus, ToolApprovalStatus.denied.rawValue)
    }

    func testCustomDenyFollowUpDoesNotUseLiveStagedContextWhenInitialSetupRuns() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: false,
            initialAgentIsRunning: false
        )
        let conversation = try fixture.dbConversation()
        let approval = exitPlanModeApproval(toolUseId: "exit-plan-1")
        fixture.context.insert(exitPlanModeApprovalRecord(conversation: conversation, approval: approval))
        try fixture.context.save()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
        fixture.viewModel.state.stagedContext = "Live staged context"

        try await fixture.viewModel.denyExitPlanMode(
            toolUseId: approval.toolUseId,
            followUp: "Please revise the plan first."
        )

        try await waitUntil("custom plan follow-up sent without live staged context during setup") {
            await fixture.agentsManager.sentMessages() == ["Please revise the plan first."]
        }

        XCTAssertTrue(try fixture.dbThread().hasCompletedInitialSetup)
        XCTAssertEqual(fixture.viewModel.state.stagedContext, "Live staged context")
    }

    func testCustomDenyFollowUpClearsWhenApprovalFails() async throws {
        let fixture = try ConversationViewModelTestFixture(
            approvalError: .approvalFailed,
            initialAgentIsRunning: false
        )
        let approval = exitPlanModeApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        do {
            try await fixture.viewModel.denyExitPlanMode(
                toolUseId: approval.toolUseId,
                followUp: "Revise it."
            )
            XCTFail("Expected denial to fail")
        } catch {}

        XCTAssertNil(fixture.viewModel.state.pendingExitPlanModeFollowUp)
        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.status, .pending)
    }
}

private func exitPlanModeApproval(toolUseId: String) -> ToolApprovalRequest {
    ToolApprovalRequest(
        sessionId: "session-123",
        toolUseId: toolUseId,
        toolName: "ExitPlanMode",
        toolInput: ##"{"plan":"# Plan\n\n- Do the work."}"##
    )
}

private func exitPlanModeApprovalRecord(
    conversation: Conversation,
    approval: ToolApprovalRequest
) -> ConversationEventRecord {
    ConversationEventRecord(
        conversationId: conversation.id,
        type: "tool_approval",
        content: approval.sessionId,
        toolId: approval.toolUseId,
        toolName: approval.toolName,
        toolInput: approval.toolInput,
        conversation: conversation
    )
}

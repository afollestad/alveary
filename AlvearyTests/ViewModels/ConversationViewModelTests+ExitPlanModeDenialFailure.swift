import AgentCLIKit
import XCTest

@testable import Alveary

/// Failed provider denial clears the follow-up that was staged before resolution.
@MainActor
extension ConversationViewModelTests {
    func testCustomDenyFollowUpClearsWhenApprovalFails() async throws {
        let fixture = try ConversationViewModelTestFixture(
            approvalError: .approvalFailed,
            initialAgentIsRunning: false
        )
        let approval = ToolApprovalRequest(
            sessionId: "session-123", toolUseId: "exit-plan-1", toolName: "ExitPlanMode",
            toolInput: ##"{"plan":"# Plan\n\n- Do the work."}"##
        )
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
        await fixture.agentsManager.pauseApprovalResolution()
        let denialTask = Task {
            try await fixture.viewModel.denyExitPlanMode(toolUseId: approval.toolUseId, followUp: "Revise it.")
        }
        do {
            try await waitUntil("denial reached the paused provider resolution") {
                await fixture.agentsManager.isApprovalResolutionPaused()
            }
            let followUp = try XCTUnwrap(fixture.viewModel.state.pendingExitPlanModeFollowUp)
            XCTAssertEqual(followUp.toolUseId, approval.toolUseId)
            XCTAssertEqual(followUp.message, "Revise it.")
            XCTAssertEqual(followUp.phase, .awaitingDeniedExitTurn)
        } catch {
            await fixture.agentsManager.resumeApprovalResolution()
            _ = await denialTask.result
            throw error
        }
        await fixture.agentsManager.resumeApprovalResolution()
        do {
            try await denialTask.value
            XCTFail("Expected denial to fail")
        } catch let error as MockAgentsManager.MockError {
            XCTAssertEqual(error, .approvalFailed)
        }
        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(calls.count, 1)
        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(call.approval.toolUseId, approval.toolUseId)
        XCTAssertEqual(call.decision, .deny)
        XCTAssertNil(fixture.viewModel.state.pendingExitPlanModeFollowUp)
        XCTAssertNil(fixture.viewModel.state.pendingExitPlanModeFollowUpQuietTask)
        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.status, .pending)
    }
}

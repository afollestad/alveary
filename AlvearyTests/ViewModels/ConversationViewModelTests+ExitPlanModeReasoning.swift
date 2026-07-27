import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testApproveExitPlanModeRestartsProviderWithStagedModelAndEffort() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true,
            providerId: "claude"
        )
        try fixture.dbThread().permissionMode = "acceptEdits"
        try fixture.dbThread().model = "sonnet"
        try fixture.context.save()
        fixture.viewModel.state.runtimePermissionMode = "acceptEdits"
        fixture.viewModel.state.runtimePlanModeEnabled = true
        let approval = exitPlanModeApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        await fixture.viewModel.applyModelChange("opus").value
        await fixture.viewModel.applyEffortChange("xhigh").value
        XCTAssertNotNil(fixture.viewModel.state.pendingSessionSettingsChange)

        try await fixture.viewModel.approveExitPlanMode(toolUseId: approval.toolUseId)

        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(calls.count, 1)
        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(call.decision, .allow)
        XCTAssertTrue(call.requiresProviderRestart)
        XCTAssertEqual(call.config.model, "opus")
        XCTAssertEqual(call.config.effort, "xhigh")
        // Everything else must match the continuation, and plan mode has to stay on or the replayed
        // ExitPlanMode is rejected with "You are not in plan mode."
        XCTAssertEqual(call.config.planModeEnabled, true)
        XCTAssertEqual(call.config.permissionMode, "acceptEdits")
        // Building this from `.nextTurn` instead of overriding a continuation config would expose
        // scheduling host tools, which a mid-turn approval resume must not gain.
        XCTAssertTrue(call.config.hostTools.isEmpty)
        XCTAssertNil(fixture.viewModel.state.pendingSessionSettingsChange)
        XCTAssertEqual(fixture.viewModel.state.liveSessionConfig?.model, "opus")
        XCTAssertFalse(fixture.viewModel.state.isReconfiguringSession)
    }

    func testApproveExitPlanModeKeepsLiveHookPathWithoutStagedReasoningChange() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true,
            providerId: "claude"
        )
        let approval = exitPlanModeApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.approveExitPlanMode(toolUseId: approval.toolUseId)

        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.requiresProviderRestart, false)
    }

    func testApproveExitPlanModeLeavesReasoningChangeStagedWhenRestartFails() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            approvalError: .approvalFailed,
            initialAgentIsRunning: true,
            providerId: "claude"
        )
        let approval = exitPlanModeApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
        await fixture.viewModel.applyModelChange("opus").value

        do {
            try await fixture.viewModel.approveExitPlanMode(toolUseId: approval.toolUseId)
            XCTFail("Expected approval to fail")
        } catch {}

        XCTAssertEqual(fixture.viewModel.state.pendingSessionSettingsChange?.pending.model, "opus")
        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.status, .pending)
        XCTAssertFalse(fixture.viewModel.state.isReconfiguringSession)
    }

    func testDenyExitPlanModeDoesNotRestartProviderWithStagedReasoningChange() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true,
            providerId: "claude"
        )
        let approval = exitPlanModeApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
        await fixture.viewModel.applyModelChange("opus").value

        try await fixture.viewModel.denyExitPlanMode(toolUseId: approval.toolUseId, followUp: "Revise it.")

        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.requiresProviderRestart, false)
        // Denial keeps planning; the follow-up is a new visible turn and consumes the change there.
        XCTAssertEqual(fixture.viewModel.state.pendingSessionSettingsChange?.pending.model, "opus")
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

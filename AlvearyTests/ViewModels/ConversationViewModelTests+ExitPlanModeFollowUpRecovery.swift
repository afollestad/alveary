import XCTest

@testable import Alveary

/// Recovery coverage for the denied-plan custom follow-up: identity rebinding across the fallback
/// deferred resubscribe, and the no-activity watchdog for follow-ups whose drain guards can no
/// longer match (for example after an app restart).
@MainActor
extension ConversationViewModelTests {
    func testCustomDenyFollowUpRebindsToResetSubscriptionAndDrainsOnTerminalToken() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let approval = exitPlanModeApproval(toolUseId: "exit-plan-1")
        await fixture.agentsManager.enableSubscription()
        fixture.viewModel.subscribe()
        try await waitUntil("subscription becomes active", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            await fixture.agentsManager.hasActiveSubscription()
        }
        let preDenyToken = try XCTUnwrap(fixture.viewModel.state.activeSubscriptionToken)
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        // No running agent, so the denial takes the fallback deferred path, which resets subscription
        // tracking and resubscribes with a fresh token mid-resolution.
        try await fixture.viewModel.denyExitPlanMode(
            toolUseId: approval.toolUseId,
            followUp: "Please revise the plan first."
        )

        let followUp = try XCTUnwrap(fixture.viewModel.state.pendingExitPlanModeFollowUp)
        XCTAssertNotEqual(followUp.sourceSubscriptionToken, preDenyToken)
        XCTAssertEqual(followUp.sourceSubscriptionToken, fixture.viewModel.state.activeSubscriptionToken)

        fixture.viewModel.handleEvent(exitPlanModeTerminalToken(for: approval))

        try await waitUntil("rebound follow-up sent after post-resume terminal token", timeout: .seconds(2)) {
            await fixture.agentsManager.sentMessages() == [exitPlanModeRevisionFollowUp()]
        }
        XCTAssertNil(fixture.viewModel.state.pendingExitPlanModeFollowUp)
    }

    func testStrandedCustomDenyFollowUpForceDrainsAfterWatchdogWindow() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        fixture.viewModel.exitPlanModeFollowUpWatchdogDelay = .milliseconds(100)
        let approval = exitPlanModeApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.denyExitPlanMode(
            toolUseId: approval.toolUseId,
            followUp: "Please revise the plan first."
        )

        // Strand the follow-up the way an app restart can: identity guards that no stream event will
        // ever satisfy again, with the quiet fallback unable to fire.
        fixture.viewModel.state.activeSubscriptionToken = UUID()
        fixture.viewModel.state.lastObservedEventIndex += 5
        fixture.viewModel.cancelPendingExitPlanModeFollowUpQuietTask()

        try await waitUntil("stranded follow-up force-drained by watchdog", timeout: .seconds(3)) {
            await fixture.agentsManager.sentMessages() == [exitPlanModeRevisionFollowUp()]
        }
        XCTAssertNil(fixture.viewModel.state.pendingExitPlanModeFollowUp)
        XCTAssertNil(fixture.viewModel.state.pendingExitPlanModeFollowUpWatchdogTask)
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

private func exitPlanModeRevisionFollowUp(_ feedback: String = "Please revise the plan first.") -> String {
    ConversationViewModel.exitPlanModeRevisionFollowUpPrompt(feedback: feedback)
}

private func exitPlanModeTerminalToken(for approval: ToolApprovalRequest) -> ConversationEvent {
    .tokens(
        input: 1,
        output: 1,
        cacheRead: 0,
        isError: false,
        stopReason: "end_turn",
        durationMs: 10,
        costUsd: 0,
        permissionDenials: [
            PermissionDenialSummary(toolName: "ExitPlanMode", toolUseId: approval.toolUseId)
        ]
    )
}

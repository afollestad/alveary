import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testCodexApplyEffortChangeReconfiguresWhenProcessIsNotRunning() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false,
            providerId: "codex"
        )

        await fixture.viewModel.applyEffortChange("high").value

        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(reconfigureCalls.count, 1)
        XCTAssertEqual(reconfigureCalls.first?.config.providerId, "codex")
        XCTAssertEqual(reconfigureCalls.first?.config.effort, "high")
        XCTAssertEqual(reconfigureCalls.first?.config.reasoningSummaryMode, .auto)
    }

    func testCodexActiveTurnEffortChangeStagesUntilNextSend() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true,
            providerId: "codex"
        )
        fixture.viewModel.state.turnState.beginTurn()

        await fixture.viewModel.applyEffortChange("high").value

        XCTAssertEqual(try fixture.dbThread().effort, "high")
        let stagedReconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(stagedReconfigureCalls.isEmpty)

        fixture.viewModel.state.turnState.endTurn()
        try await fixture.viewModel.queueOrSend("Next Codex turn")

        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(reconfigureCalls.count, 1)
        XCTAssertEqual(reconfigureCalls.first?.config.providerId, "codex")
        XCTAssertEqual(reconfigureCalls.first?.config.effort, "high")
        XCTAssertEqual(reconfigureCalls.first?.config.reasoningSummaryMode, .auto)
        XCTAssertNil(fixture.viewModel.state.pendingSessionSettingsChange)
    }

    func testCodexStagedEffortDoesNotAffectDeferredApprovalResumeConfig() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false,
            providerId: "codex"
        )
        try fixture.dbThread().permissionMode = "on-request"
        try fixture.context.save()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(
            request: ToolApprovalRequest(
                sessionId: "session-123",
                toolUseId: "tool-1",
                toolName: "Bash",
                toolInput: "{\"command\":\"swift test\"}"
            ),
            status: .pending
        )

        await fixture.viewModel.applyEffortChange("high").value
        try await fixture.viewModel.approveToolUse(toolUseId: "tool-1")

        let approvalCalls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(approvalCalls.count, 1)
        XCTAssertEqual(approvalCalls.first?.config.providerId, "codex")
        XCTAssertEqual(approvalCalls.first?.config.effort, "medium")
        XCTAssertEqual(try fixture.dbThread().effort, "high")
        XCTAssertEqual(fixture.viewModel.state.pendingSessionSettingsChange?.pending.effort, "high")
    }

    func testCodexStagedEffortAppliesToFreshSessionHandoff() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true,
            providerId: "codex"
        )
        fixture.viewModel.state.turnState.beginTurn()

        await fixture.viewModel.applyEffortChange("high").value
        fixture.viewModel.state.turnState.endTurn()
        await fixture.viewModel.finishHiddenSessionHandoff(with: "Carry this context forward.")

        let freshSessionCalls = await fixture.agentsManager.freshSessionCalls()
        XCTAssertEqual(freshSessionCalls.count, 1)
        XCTAssertEqual(freshSessionCalls.first?.config.providerId, "codex")
        XCTAssertEqual(freshSessionCalls.first?.config.effort, "high")
        XCTAssertNil(fixture.viewModel.state.pendingSessionSettingsChange)
    }
}

import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testApplyEffortChangeStagesDuringActiveTurnUntilNextSend() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true
        )
        fixture.viewModel.state.turnState.beginTurn()

        await fixture.viewModel.applyEffortChange("high").value

        XCTAssertEqual(try fixture.dbThread().effort, "high")
        XCTAssertEqual(fixture.viewModel.state.pendingSessionSettingsChange?.pending.effort, "high")
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)

        fixture.viewModel.state.turnState.endTurn()
        try await fixture.viewModel.queueOrSend("Next turn")

        let appliedReconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(appliedReconfigureCalls.count, 1)
        XCTAssertEqual(appliedReconfigureCalls.first?.config.effort, "high")
        XCTAssertNil(fixture.viewModel.state.pendingSessionSettingsChange)
    }

    func testApplyEffortChangeStagesWhileRuntimeBusy() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true
        )
        await fixture.agentsManager.setStatus(.busy, for: fixture.conversation.id)

        await fixture.viewModel.applyEffortChange("high").value

        XCTAssertEqual(try fixture.dbThread().effort, "high")
        XCTAssertEqual(fixture.viewModel.state.pendingSessionSettingsChange?.pending.effort, "high")
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testApplyPermissionModeChangeStagesDuringActiveTurnWithoutChangingLiveMode() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true
        )
        try fixture.dbThread().permissionMode = "default"
        try fixture.context.save()
        fixture.viewModel.state.turnState.beginTurn()

        await fixture.viewModel.applyPermissionModeChange("acceptEdits").value

        XCTAssertEqual(try fixture.dbThread().permissionMode, "acceptEdits")
        XCTAssertEqual(fixture.viewModel.state.runtimePermissionMode, nil)
        XCTAssertEqual(fixture.viewModel.pendingPermissionModeForDisplay(), "acceptEdits")
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testStagedPermissionModeDoesNotChangeEffectivePermissionModeBeforeNextTurn() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true
        )
        try fixture.dbThread().permissionMode = "default"
        try fixture.context.save()
        fixture.viewModel.state.turnState.beginTurn()

        await fixture.viewModel.applyPermissionModeChange("acceptEdits").value

        XCTAssertEqual(try fixture.dbThread().permissionMode, "acceptEdits")
        XCTAssertEqual(fixture.viewModel.pendingPermissionModeForDisplay(), "acceptEdits")
        XCTAssertEqual(fixture.viewModel.effectivePermissionMode, "default")
    }

    func testApplyPermissionModeChangeStagesDuringPendingToolApproval() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false
        )
        try fixture.dbThread().permissionMode = "default"
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

        await fixture.viewModel.applyPermissionModeChange("acceptEdits").value

        XCTAssertEqual(try fixture.dbThread().permissionMode, "acceptEdits")
        XCTAssertEqual(fixture.viewModel.pendingPermissionModeForDisplay(), "acceptEdits")
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testRuntimePermissionModeChangePersistsWhileNonPermissionSettingIsStaged() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true
        )
        try fixture.dbThread().permissionMode = "default"
        try fixture.context.save()
        fixture.viewModel.state.turnState.beginTurn()

        await fixture.viewModel.applyEffortChange("high").value
        fixture.viewModel.handleEvent(.permissionModeChanged("plan"))

        XCTAssertEqual(try fixture.dbThread().permissionMode, "plan")
        XCTAssertEqual(fixture.viewModel.state.runtimePermissionMode, "plan")
        XCTAssertEqual(fixture.viewModel.state.pendingSessionSettingsChange?.pending.effort, "high")
    }

    func testFailedStagedEffortApplyDoesNotRollbackLivePermissionModeChange() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            reconfigureError: .reconfigureFailed,
            initialAgentIsRunning: true
        )
        try fixture.dbThread().permissionMode = "default"
        try fixture.context.save()
        fixture.viewModel.state.turnState.beginTurn()

        await fixture.viewModel.applyEffortChange("high").value
        fixture.viewModel.handleEvent(.permissionModeChanged("plan"))
        fixture.viewModel.state.turnState.endTurn()

        do {
            try await fixture.viewModel.queueOrSend("Next turn")
            XCTFail("Expected staged settings apply to fail")
        } catch {
            XCTAssertEqual(error as? MockAgentsManager.MockError, .reconfigureFailed)
        }

        XCTAssertEqual(try fixture.dbThread().effort, "medium")
        XCTAssertEqual(try fixture.dbThread().permissionMode, "plan")
        XCTAssertEqual(fixture.viewModel.state.runtimePermissionMode, "plan")
        XCTAssertNil(fixture.viewModel.state.pendingSessionSettingsChange)
    }

    func testRuntimePermissionModeChangeDoesNotOverwriteStagedPermissionMode() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true
        )
        try fixture.dbThread().permissionMode = "default"
        try fixture.context.save()
        fixture.viewModel.state.turnState.beginTurn()

        await fixture.viewModel.applyPermissionModeChange("acceptEdits").value
        fixture.viewModel.handleEvent(.permissionModeChanged("plan"))

        XCTAssertEqual(try fixture.dbThread().permissionMode, "acceptEdits")
        XCTAssertEqual(fixture.viewModel.state.runtimePermissionMode, "plan")
        XCTAssertEqual(fixture.viewModel.pendingPermissionModeForDisplay(), "acceptEdits")
    }

    func testApplyPermissionModeChangeStagesWhilePromptIsUnanswered() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false
        )
        try fixture.dbThread().permissionMode = "default"
        try fixture.context.save()
        let conversation = try fixture.dbConversation()
        let promptRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_call",
            toolId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#,
            conversation: conversation
        )
        fixture.context.insert(promptRecord)
        fixture.viewModel.state.grouper.append(event: promptRecord)

        await fixture.viewModel.applyPermissionModeChange("acceptEdits").value

        XCTAssertEqual(try fixture.dbThread().permissionMode, "acceptEdits")
        XCTAssertEqual(fixture.viewModel.pendingPermissionModeForDisplay(), "acceptEdits")
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testApplyModelChangeStagesDuringActiveTurn() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true
        )
        try fixture.dbThread().model = "sonnet"
        try fixture.context.save()
        fixture.viewModel.state.turnState.beginTurn()

        await fixture.viewModel.applyModelChange("opus").value

        XCTAssertEqual(try fixture.dbThread().model, "opus")
        XCTAssertEqual(fixture.viewModel.state.pendingSessionSettingsChange?.pending.model, "opus")
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }
}

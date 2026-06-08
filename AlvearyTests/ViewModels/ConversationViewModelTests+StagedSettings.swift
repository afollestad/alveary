import Foundation
import SwiftData
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

    func testApplyPlanModeChangeStagesDuringActiveTurnWithoutChangingLiveMode() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true
        )
        try fixture.dbThread().permissionMode = "acceptEdits"
        try fixture.context.save()
        fixture.viewModel.state.runtimePlanModeEnabled = false
        fixture.viewModel.state.turnState.beginTurn()

        await fixture.viewModel.applyPlanModeChange(true).value

        XCTAssertEqual(try fixture.dbThread().permissionMode, "acceptEdits")
        XCTAssertEqual(try fixture.dbThread().planModeEnabled, true)
        XCTAssertEqual(fixture.viewModel.state.runtimePlanModeEnabled, false)
        XCTAssertEqual(fixture.viewModel.effectivePlanModeEnabled, false)
        XCTAssertEqual(fixture.viewModel.pendingPlanModeForDisplay(), true)
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testApplyPlanModeChangeCanCancelDisplayedPendingEnableWhenStoredValueIsAlreadyFalse() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true
        )
        try fixture.dbThread().permissionMode = "acceptEdits"
        try fixture.dbThread().planModeEnabled = false
        try fixture.context.save()
        fixture.viewModel.state.runtimePlanModeEnabled = false
        fixture.viewModel.state.turnState.beginTurn()

        let original = fixture.viewModel.sessionSettingsSnapshot(for: try fixture.dbThread())
        var pending = original
        pending.planModeEnabled = true
        fixture.viewModel.state.pendingSessionSettingsChange = PendingSessionSettingsChange(
            original: original,
            pending: pending,
            liveSessionConfig: nil
        )

        await fixture.viewModel.applyPlanModeChange(false).value

        XCTAssertEqual(try fixture.dbThread().planModeEnabled, false)
        XCTAssertEqual(fixture.viewModel.state.runtimePlanModeEnabled, false)
        XCTAssertNil(fixture.viewModel.pendingPlanModeForDisplay())
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testApplyPlanModeChangeCanExitDisplayedRuntimePlanModeWhenStoredValueIsAlreadyFalse() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false
        )
        try fixture.dbThread().permissionMode = "acceptEdits"
        try fixture.dbThread().planModeEnabled = false
        try fixture.context.save()
        fixture.viewModel.state.runtimePlanModeEnabled = true

        await fixture.viewModel.applyPlanModeChange(false).value

        XCTAssertEqual(try fixture.dbThread().planModeEnabled, false)
        XCTAssertEqual(fixture.viewModel.state.runtimePlanModeEnabled, true)
        XCTAssertEqual(fixture.viewModel.pendingPlanModeForDisplay(), false)
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testClaudeInactivePlanModeChangeStagesWithoutReconfiguring() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true,
            providerId: "claude"
        )
        try fixture.dbThread().permissionMode = "acceptEdits"
        try fixture.dbThread().planModeEnabled = false
        try fixture.context.save()
        fixture.viewModel.state.runtimePlanModeEnabled = false

        await fixture.viewModel.applyPlanModeChange(true).value

        XCTAssertEqual(try fixture.dbThread().planModeEnabled, true)
        XCTAssertEqual(fixture.viewModel.state.runtimePlanModeEnabled, false)
        XCTAssertEqual(fixture.viewModel.pendingPlanModeForDisplay(), true)
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)

        try await fixture.viewModel.queueOrSend("Next turn")

        let appliedReconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(appliedReconfigureCalls.count, 1)
        XCTAssertEqual(appliedReconfigureCalls.first?.config.providerId, "claude")
        XCTAssertEqual(appliedReconfigureCalls.first?.config.planModeEnabled, true)
        XCTAssertEqual(fixture.viewModel.state.runtimePlanModeEnabled, true)
        XCTAssertNil(fixture.viewModel.state.pendingSessionSettingsChange)
    }

    func testClaudeInactivePlanModeExitStagesDisplayedOffWithoutReconfiguring() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true,
            providerId: "claude"
        )
        try fixture.dbThread().permissionMode = "acceptEdits"
        try fixture.dbThread().planModeEnabled = true
        try fixture.context.save()
        fixture.viewModel.state.runtimePlanModeEnabled = true

        await fixture.viewModel.applyPlanModeChange(false).value

        XCTAssertEqual(try fixture.dbThread().planModeEnabled, false)
        XCTAssertEqual(fixture.viewModel.state.runtimePlanModeEnabled, true)
        XCTAssertEqual(fixture.viewModel.pendingPlanModeForDisplay(), false)
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testClaudeInactiveComposerSettingsApplyTogetherOnNextTurn() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false,
            providerId: "claude"
        )
        try fixture.dbThread().permissionMode = "default"
        try fixture.dbThread().planModeEnabled = false
        try fixture.context.save()
        fixture.viewModel.state.runtimePlanModeEnabled = false

        await fixture.viewModel.applyModelChange("opus").value
        await fixture.viewModel.applyEffortChange("high").value
        await fixture.viewModel.applyPermissionModeChange("acceptEdits").value
        await fixture.viewModel.applyPlanModeChange(true).value

        XCTAssertEqual(try fixture.dbThread().model, "opus")
        XCTAssertEqual(try fixture.dbThread().effort, "high")
        XCTAssertEqual(try fixture.dbThread().permissionMode, "acceptEdits")
        XCTAssertEqual(try fixture.dbThread().planModeEnabled, true)
        XCTAssertEqual(fixture.viewModel.state.pendingSessionSettingsChange?.pending.model, "opus")
        XCTAssertEqual(fixture.viewModel.state.pendingSessionSettingsChange?.pending.effort, "high")
        XCTAssertEqual(fixture.viewModel.pendingPermissionModeForDisplay(), "acceptEdits")
        XCTAssertEqual(fixture.viewModel.pendingPlanModeForDisplay(), true)
        var reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)

        var invalidations = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.type == ConversationEventRecord.contextWindowInvalidatedType
        }
        XCTAssertTrue(invalidations.isEmpty)

        try await fixture.viewModel.queueOrSend("Next turn")

        reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(reconfigureCalls.count, 1)
        XCTAssertEqual(reconfigureCalls.first?.config.providerId, "claude")
        XCTAssertEqual(reconfigureCalls.first?.config.model, "opus")
        XCTAssertEqual(reconfigureCalls.first?.config.effort, "high")
        XCTAssertEqual(reconfigureCalls.first?.config.permissionMode, "acceptEdits")
        XCTAssertEqual(reconfigureCalls.first?.config.planModeEnabled, true)
        XCTAssertEqual(fixture.viewModel.state.runtimePermissionMode, "acceptEdits")
        XCTAssertEqual(fixture.viewModel.state.runtimePlanModeEnabled, true)
        XCTAssertNil(fixture.viewModel.state.pendingSessionSettingsChange)

        invalidations = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.type == ConversationEventRecord.contextWindowInvalidatedType
        }
        XCTAssertEqual(invalidations.count, 1)
        XCTAssertEqual(invalidations.first?.conversationId, fixture.conversation.id)
    }

    func testStagedPlanModeAppliesOnNextTurn() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true
        )
        try fixture.dbThread().permissionMode = "acceptEdits"
        try fixture.context.save()
        fixture.viewModel.state.runtimePlanModeEnabled = false
        fixture.viewModel.state.turnState.beginTurn()

        await fixture.viewModel.applyPlanModeChange(true).value
        fixture.viewModel.state.turnState.endTurn()
        try await fixture.viewModel.queueOrSend("Next turn")

        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(reconfigureCalls.count, 1)
        XCTAssertEqual(reconfigureCalls.first?.config.permissionMode, "acceptEdits")
        XCTAssertEqual(reconfigureCalls.first?.config.planModeEnabled, true)
        XCTAssertEqual(fixture.viewModel.state.runtimePlanModeEnabled, true)
        XCTAssertNil(fixture.viewModel.state.pendingSessionSettingsChange)
    }

    func testPlanModeNextTurnRequiredKeepsLiveStateAndStagesChange() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            reconfigureResult: .nextTurnRequired,
            initialAgentIsRunning: false,
            providerId: "codex"
        )
        try fixture.dbThread().permissionMode = "on-request"
        try fixture.context.save()
        fixture.viewModel.state.runtimePlanModeEnabled = false

        await fixture.viewModel.applyPlanModeChange(true).value

        XCTAssertEqual(try fixture.dbThread().planModeEnabled, true)
        XCTAssertEqual(fixture.viewModel.state.runtimePlanModeEnabled, false)
        XCTAssertEqual(fixture.viewModel.effectivePlanModeEnabled, false)
        XCTAssertEqual(fixture.viewModel.pendingPlanModeForDisplay(), true)
        XCTAssertEqual(fixture.viewModel.state.pendingSessionSettingsChange?.original.planModeEnabled, false)
        XCTAssertEqual(fixture.viewModel.state.pendingSessionSettingsChange?.pending.planModeEnabled, true)
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(reconfigureCalls.count, 1)
        XCTAssertEqual(reconfigureCalls.first?.config.planModeEnabled, true)
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

        XCTAssertEqual(try fixture.dbThread().permissionMode, "default")
        XCTAssertEqual(try fixture.dbThread().planModeEnabled, true)
        XCTAssertEqual(fixture.viewModel.state.runtimePermissionMode, "default")
        XCTAssertEqual(fixture.viewModel.state.runtimePlanModeEnabled, true)
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
        XCTAssertEqual(try fixture.dbThread().permissionMode, "default")
        XCTAssertEqual(try fixture.dbThread().planModeEnabled, true)
        XCTAssertEqual(fixture.viewModel.state.runtimePermissionMode, "default")
        XCTAssertEqual(fixture.viewModel.state.runtimePlanModeEnabled, true)
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
        XCTAssertEqual(try fixture.dbThread().planModeEnabled, true)
        XCTAssertEqual(fixture.viewModel.state.runtimePermissionMode, "default")
        XCTAssertEqual(fixture.viewModel.state.runtimePlanModeEnabled, true)
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

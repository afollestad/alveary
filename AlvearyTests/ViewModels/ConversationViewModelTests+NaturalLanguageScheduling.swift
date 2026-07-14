import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testOrdinaryProjectAndTaskConfigsExposeOnlySchedulingTools() throws {
        let projectFixture = try ConversationViewModelTestFixture()
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }

        let expectedNames = [
            ScheduledTaskHostToolCatalog.listToolName,
            ScheduledTaskHostToolCatalog.proposeToolName
        ]
        let projectConfig = try projectFixture.viewModel.makeSpawnConfig()
        let taskConfig = try scheduledFixture.fixture.viewModel.makeSpawnConfig()
        let continuationConfig = try projectFixture.viewModel.makeSpawnConfig(settingsSource: .currentContinuation)

        XCTAssertEqual(projectConfig.hostTools.map(\.name), expectedNames)
        XCTAssertEqual(taskConfig.hostTools.map(\.name), expectedNames)
        XCTAssertTrue(continuationConfig.hostTools.isEmpty)
    }

    func testOrdinaryOutboundUpgradesReadyRuntimeWithoutSchedulingTools() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        fixture.viewModel.state.liveSessionConfig = try fixture.viewModel.makeSpawnConfig(
            settingsSource: .currentContinuation
        )

        _ = try await fixture.viewModel.prepareRuntimeForOutbound()

        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        let reconfigure = try XCTUnwrap(reconfigureCalls.first)
        XCTAssertEqual(reconfigureCalls.count, 1)
        XCTAssertEqual(
            reconfigure.config.hostTools.map(\.name),
            [ScheduledTaskHostToolCatalog.listToolName, ScheduledTaskHostToolCatalog.proposeToolName]
        )
    }

    func testDeferredApprovalForcesNextOrdinaryOutboundToReplacePossibleToolFreeRespawn() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        fixture.viewModel.state.liveSessionConfig = try fixture.viewModel.makeSpawnConfig()
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test\"}"
        )
        fixture.viewModel.handleEvent(.toolApprovalRequested(approval))

        try await fixture.viewModel.approveToolUse(toolUseId: approval.toolUseId)

        let approvalCalls = await fixture.agentsManager.approvalCalls()
        let approvalCall = try XCTUnwrap(approvalCalls.first)
        XCTAssertTrue(approvalCall.config.hostTools.isEmpty)
        XCTAssertTrue(fixture.viewModel.state.requiresSchedulingHostToolReplacement)

        _ = try await fixture.viewModel.prepareRuntimeForOutbound()

        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        let reconfigureCall = try XCTUnwrap(reconfigureCalls.first)
        XCTAssertEqual(
            reconfigureCall.config.hostTools.map(\.name),
            [ScheduledTaskHostToolCatalog.listToolName, ScheduledTaskHostToolCatalog.proposeToolName]
        )
        XCTAssertFalse(fixture.viewModel.state.requiresSchedulingHostToolReplacement)
    }

    func testSuppressedPromptDenialForcesNextOrdinaryOutboundToReplacePossibleToolFreeRespawn() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        fixture.viewModel.state.liveSessionConfig = try fixture.viewModel.makeSpawnConfig()
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: "{}"
        )

        try await fixture.viewModel.denySuppressedPromptApproval(approval)

        let approvalCalls = await fixture.agentsManager.approvalCalls()
        XCTAssertTrue(try XCTUnwrap(approvalCalls.first).config.hostTools.isEmpty)
        XCTAssertTrue(fixture.viewModel.state.requiresSchedulingHostToolReplacement)

        _ = try await fixture.viewModel.prepareRuntimeForOutbound()

        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(
            try XCTUnwrap(reconfigureCalls.first).config.hostTools.map(\.name),
            [ScheduledTaskHostToolCatalog.listToolName, ScheduledTaskHostToolCatalog.proposeToolName]
        )
        XCTAssertFalse(fixture.viewModel.state.requiresSchedulingHostToolReplacement)
    }

    func testHostToolDiagnosticDuringSpawnWinsOverSuccessfulTransitionCompletion() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let config = try fixture.viewModel.makeSpawnConfig()
        await fixture.agentsManager.pauseNextSpawn()
        let startTask = Task { @MainActor in
            try await fixture.viewModel.startAgentReserved(config: config)
        }
        await fixture.agentsManager.waitUntilSpawnEntered()

        fixture.viewModel.state.markSchedulingHostToolsUnavailable(requiresRuntimeReplacement: true)
        await fixture.agentsManager.resumePausedSpawn()
        try await startTask.value

        XCTAssertTrue(fixture.viewModel.state.schedulingHostToolsDisabled)
        XCTAssertTrue(fixture.viewModel.state.requiresSchedulingHostToolReplacement)
        XCTAssertTrue(try XCTUnwrap(fixture.viewModel.state.liveSessionConfig).hostTools.isEmpty)
    }

    func testFailedRuntimeTransitionRestoresExistingHostToolReplacementRequirement() async throws {
        let fixture = try ConversationViewModelTestFixture(
            reconfigureError: .reconfigureFailed,
            initialAgentIsRunning: true
        )
        fixture.viewModel.state.invalidateSchedulingHostToolRuntimeConfiguration()

        do {
            _ = try await fixture.viewModel.prepareRuntimeForOutbound()
            XCTFail("Expected reconfigure to fail")
        } catch MockAgentsManager.MockError.reconfigureFailed {}

        XCTAssertTrue(fixture.viewModel.state.requiresSchedulingHostToolReplacement)
    }

    func testSessionHandoffSteeringRetainsSchedulingHostToolDiagnostic() throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.markSchedulingHostToolsUnavailable(requiresRuntimeReplacement: false)
        let notice = fixture.viewModel.state.sessionContinuityNotice

        fixture.viewModel.beginSessionHandoffSteeringPrompt(startsCountdown: false)

        XCTAssertEqual(fixture.viewModel.state.sessionContinuityNotice, notice)
    }

    func testManualFollowUpResumesAutomatedSessionWithSchedulingTools() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        try await fixture.viewModel.startAutomatedScheduledTurn("Run the scheduled audit.")
        fixture.viewModel.state.endTurn()
        try scheduledFixture.markRunTerminal()

        try await fixture.viewModel.send("Continue manually.")

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        let suspendCalls = await fixture.agentsManager.suspendCalls()
        let destroyCalls = await fixture.agentsManager.destroyCalls()
        XCTAssertEqual(spawnCalls.count, 2)
        XCTAssertTrue(spawnCalls[0].config.isAutomatedScheduledTurn)
        XCTAssertFalse(spawnCalls[1].config.isAutomatedScheduledTurn)
        XCTAssertTrue(spawnCalls[0].config.hostTools.isEmpty)
        XCTAssertEqual(
            spawnCalls[1].config.hostTools.map(\.name),
            [ScheduledTaskHostToolCatalog.listToolName, ScheduledTaskHostToolCatalog.proposeToolName]
        )
        XCTAssertFalse(spawnCalls[1].forkSession)
        XCTAssertEqual(suspendCalls, [fixture.conversation.id])
        XCTAssertTrue(destroyCalls.isEmpty)
    }
}

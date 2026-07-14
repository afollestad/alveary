import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testCompletedSetupStillDefersManualOutboundForPersistedActiveScheduledRun() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        fixture.thread.hasCompletedInitialSetup = true
        let run = try XCTUnwrap(fixture.thread.scheduledTaskRun)
        run.status = .running
        try fixture.context.save()

        do {
            try await fixture.viewModel.send("Do not preempt the restored scheduled run.")
            XCTFail("Expected manual outbound to wait for persisted scheduled completion")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Wait for the scheduled task's initial turn to finish"
            )
        }

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(spawnCalls.isEmpty)
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testCompletedSetupStillDefersManualOutboundForUnknownScheduledRunStatus() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        fixture.thread.hasCompletedInitialSetup = true
        let run = try XCTUnwrap(fixture.thread.scheduledTaskRun)
        run.statusRawValue = "future-status"
        try fixture.context.save()

        do {
            try await fixture.viewModel.send("Do not bypass the restored scheduled run.")
            XCTFail("Expected manual outbound to wait for a known terminal scheduled status")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Wait for the scheduled task's initial turn to finish"
            )
        }

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(spawnCalls.isEmpty)
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testScheduledFinalizationSuppressesAutomaticSessionHandoff() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        fixture.viewModel.beginAutomatedScheduledRunExecution()
        defer { fixture.viewModel.finishAutomatedScheduledRunExecution() }
        fixture.viewModel.state.isAutomaticSessionHandoffPending = true

        fixture.viewModel.handleEvent(.tokens(
            input: 190,
            output: 5,
            cacheRead: 0,
            isError: false,
            stopReason: "end_turn",
            durationMs: 10,
            costUsd: 0.01,
            contextWindowSize: 200,
            permissionDenials: []
        ))
        await Task.yield()

        XCTAssertFalse(fixture.viewModel.state.isAutomaticSessionHandoffPending)
        XCTAssertFalse(fixture.viewModel.state.hasActiveSessionHandoff)
        let sentMessages = await fixture.agentsManager.sentMessages()
        let freshSessionCalls = await fixture.agentsManager.freshSessionCalls()
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertTrue(freshSessionCalls.isEmpty)
    }

    func testScheduledFinalizationBlocksHiddenCommitGenerationAndSessionHandoff() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        fixture.thread.hasCompletedInitialSetup = true
        try scheduledFixture.markRunTerminal()
        fixture.viewModel.beginAutomatedScheduledRunExecution()
        defer { fixture.viewModel.finishAutomatedScheduledRunExecution() }

        do {
            _ = try await fixture.viewModel.generateCommitMessage("Generate a commit message.")
            XCTFail("Expected hidden commit generation to wait for scheduled finalization")
        } catch {
            XCTAssertEqual(error as? CommitMessageGenerationError, .busy)
        }

        await fixture.viewModel.startSessionHandoff(trigger: .manual)

        XCTAssertFalse(fixture.viewModel.state.hasActiveSessionHandoff)
        XCTAssertEqual(
            fixture.viewModel.lastTurnError,
            "Wait for the scheduled task's initial turn to finish."
        )
        let sentMessages = await fixture.agentsManager.sentMessages()
        let freshSessionCalls = await fixture.agentsManager.freshSessionCalls()
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertTrue(freshSessionCalls.isEmpty)
    }

    func testScheduledFinalizationBlocksSettingsWritesAndDirectReconfiguration() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        fixture.thread.hasCompletedInitialSetup = true
        try scheduledFixture.markRunTerminal()
        fixture.viewModel.beginAutomatedScheduledRunExecution()
        defer { fixture.viewModel.finishAutomatedScheduledRunExecution() }

        await fixture.viewModel.applyModelChange("opus").value
        XCTAssertNil(fixture.thread.model)

        do {
            try await fixture.viewModel.reconfigureSession(config: fixture.viewModel.makeSpawnConfig())
            XCTFail("Expected direct reconfiguration to wait for scheduled finalization")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Wait for the scheduled task's initial turn to finish"
            )
        }

        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testTerminalScheduledTaskHiddenCommitRespawnDropsAutomatedRestrictions() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        try await fixture.viewModel.startAutomatedScheduledTurn("Run the scheduled audit.")
        fixture.viewModel.state.endTurn()
        try scheduledFixture.markRunTerminal()
        await fixture.agentsManager.kill(conversationId: fixture.conversation.id)

        let generation = Task {
            try await fixture.viewModel.generateCommitMessage("Generate a commit message.")
        }
        try await waitUntil("terminal scheduled commit generation respawned") {
            await fixture.agentsManager.spawnCalls().count == 2
        }

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertTrue(spawnCalls[0].config.isAutomatedScheduledTurn)
        XCTAssertFalse(spawnCalls[1].config.isAutomatedScheduledTurn)

        fixture.viewModel.handleEvent(.message(
            role: "assistant",
            content: "Keep manual restrictions.",
            parentToolUseId: nil
        ))
        fixture.viewModel.handleEvent(.runtimeActivity(state: .idle, turnId: nil, outcome: .completed))
        let generatedMessage = try await generation.value
        XCTAssertEqual(generatedMessage, "Keep manual restrictions.")
    }

    func testTerminalScheduledTaskHiddenHandoffRespawnDropsAutomatedRestrictions() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        try await fixture.viewModel.startAutomatedScheduledTurn("Run the scheduled audit.")
        fixture.viewModel.state.endTurn()
        try scheduledFixture.markRunTerminal()
        await fixture.agentsManager.kill(conversationId: fixture.conversation.id)

        await fixture.viewModel.startSessionHandoff(trigger: .manual)

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertEqual(spawnCalls.count, 2)
        XCTAssertTrue(spawnCalls[0].config.isAutomatedScheduledTurn)
        XCTAssertFalse(spawnCalls[1].config.isAutomatedScheduledTurn)
        fixture.viewModel.handleEvent(.error(message: "End the hidden handoff test."))
    }
}

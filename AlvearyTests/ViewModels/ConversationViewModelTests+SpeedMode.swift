import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testSpeedModeDefaultsAndUnknownValuesNormalizeToStandard() throws {
        let fixture = try ConversationViewModelTestFixture()
        let thread = try fixture.dbThread()

        thread.speedMode = nil
        XCTAssertEqual(thread.normalizedSpeedMode, .standard)
        XCTAssertEqual(try fixture.viewModel.makeSpawnConfig().speedMode, .standard)

        thread.speedMode = "turbo"
        XCTAssertEqual(thread.normalizedSpeedMode, .standard)
        XCTAssertEqual(try fixture.viewModel.makeSpawnConfig().speedMode, .standard)
    }

    func testApplySpeedModeChangeStagesDuringActiveTurnUntilNextSend() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true,
            providerId: "codex"
        )
        fixture.viewModel.state.runtimeSpeedMode = .standard
        fixture.viewModel.state.turnState.beginTurn()

        await fixture.viewModel.applySpeedModeChange(.fast, supportsSpeedMode: true).value

        XCTAssertEqual(try fixture.dbThread().normalizedSpeedMode, .fast)
        XCTAssertEqual(fixture.viewModel.state.runtimeSpeedMode, .standard)
        XCTAssertEqual(fixture.viewModel.pendingSpeedModeForDisplay(), .fast)
        var reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)

        fixture.viewModel.state.turnState.endTurn()
        try await fixture.viewModel.queueOrSend("Next turn")

        reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(reconfigureCalls.count, 1)
        XCTAssertEqual(reconfigureCalls.first?.config.speedMode, .fast)
        XCTAssertEqual(fixture.viewModel.state.runtimeSpeedMode, .fast)
        XCTAssertNil(fixture.viewModel.state.pendingSessionSettingsChange)
    }

    func testExplicitFastSelectionRejectsUnsupportedProviderWithoutChangingThread() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "claude")

        await fixture.viewModel.applySpeedModeChange(.fast, supportsSpeedMode: false).value

        XCTAssertEqual(try fixture.dbThread().normalizedSpeedMode, .standard)
        XCTAssertEqual(fixture.viewModel.lastTurnError, "Fast mode is not supported by this provider.")
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testUnsupportedProviderStatusNormalizesStoredFastBeforeSend() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "claude")
        try fixture.dbThread().speedMode = AgentSpeedMode.fast.rawValue
        try fixture.context.save()

        fixture.viewModel.normalizeUnsupportedSpeedModeIfNeeded(supportsSpeedMode: false)

        XCTAssertEqual(try fixture.dbThread().normalizedSpeedMode, .standard)
        XCTAssertEqual(fixture.viewModel.state.runtimeSpeedMode, .standard)
    }

    func testPreStartupProviderModelChangeForcesFastOffWhenTargetProviderDoesNotSupportSpeed() throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: false,
            initialAgentIsRunning: false,
            providerId: "codex"
        )
        try fixture.dbThread().speedMode = AgentSpeedMode.fast.rawValue
        try fixture.context.save()

        let didApply = fixture.viewModel.applyPreStartupProviderModelChange(
            providerID: "claude",
            model: "opus",
            effortOptions: [],
            defaultEffort: nil,
            supportsSpeedMode: false
        )

        XCTAssertTrue(didApply)
        XCTAssertEqual(try fixture.dbConversation().provider, "claude")
        XCTAssertEqual(try fixture.dbThread().normalizedSpeedMode, .standard)
        XCTAssertEqual(fixture.viewModel.state.runtimeSpeedMode, .standard)
    }

    func testPreStartupModelChangeForcesFastOffWhenCurrentProviderReportsNoSpeedSupport() throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: false,
            initialAgentIsRunning: false,
            providerId: "codex"
        )
        try fixture.dbThread().speedMode = AgentSpeedMode.fast.rawValue
        fixture.viewModel.state.runtimeSpeedMode = .fast
        try fixture.context.save()

        let didApply = fixture.viewModel.applyPreStartupProviderModelChange(
            providerID: "codex",
            model: "gpt-5.5",
            effortOptions: [],
            defaultEffort: nil,
            supportsSpeedMode: false
        )

        XCTAssertTrue(didApply)
        XCTAssertEqual(try fixture.dbThread().normalizedSpeedMode, .standard)
        XCTAssertEqual(fixture.viewModel.state.runtimeSpeedMode, .standard)
        XCTAssertEqual(try fixture.viewModel.makeSpawnConfig().speedMode, .standard)
    }

    func testModelChangeForcesFastOffWhenCurrentProviderNoLongerSupportsSpeed() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: false,
            initialAgentIsRunning: false,
            providerId: "codex"
        )
        try fixture.dbThread().speedMode = AgentSpeedMode.fast.rawValue
        try fixture.context.save()
        fixture.viewModel.state.runtimeSpeedMode = .fast

        await fixture.viewModel.applyModelChange("gpt-5.5", supportsSpeedMode: false).value

        XCTAssertEqual(try fixture.dbThread().normalizedSpeedMode, .standard)
        XCTAssertEqual(fixture.viewModel.state.runtimeSpeedMode, .standard)
        XCTAssertEqual(try fixture.viewModel.makeSpawnConfig().speedMode, .standard)
    }

    func testQueuedFastIntentDoesNotAffectOlderQueuedMessages() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true,
            providerId: "codex"
        )
        fixture.viewModel.state.runtimeSpeedMode = .standard
        fixture.viewModel.state.turnState.beginTurn()

        try await fixture.viewModel.queueOrSend("Older queued")
        try await fixture.viewModel.queueOrSend("Fast queued", requiredSpeedMode: .fast)

        XCTAssertEqual(fixture.viewModel.messageQueue.pending.map(\.text), ["Older queued", "Fast queued"])
        XCTAssertEqual(fixture.viewModel.messageQueue.pending.map(\.requiredSpeedMode), [nil, .fast])

        fixture.viewModel.state.turnState.endTurn()
        fixture.viewModel.handleTurnCompleted()

        try await waitUntil("older queued message sent first") {
            await fixture.agentsManager.sentMessages() == ["Older queued"]
        }
        var reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)

        fixture.viewModel.handleEvent(.tokens(
            input: 1,
            output: 1,
            cacheRead: 0,
            isError: false,
            stopReason: "end_turn",
            durationMs: 10,
            costUsd: 0,
            permissionDenials: []
        ))

        try await waitUntil("fast queued message sent") {
            await fixture.agentsManager.sentMessages() == ["Older queued", "Fast queued"]
        }
        reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(reconfigureCalls.count, 1)
        XCTAssertEqual(reconfigureCalls.first?.config.speedMode, .fast)
    }

    func testSteerQueuedMessageRejectsSpeedIntent() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        fixture.viewModel.turnState.beginTurn()
        fixture.viewModel.state.activeRuntimeActivityTurnId = "turn-1"
        try await fixture.viewModel.queueOrSend("Fast queued", requiredSpeedMode: .fast)

        let queuedID = try XCTUnwrap(fixture.viewModel.messageQueue.peekNext()?.id)
        do {
            try await fixture.viewModel.steerQueuedMessage(id: queuedID)
            XCTFail("Expected speed-mode queued message steering to fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Speed-mode queued messages send on the next turn")
        }

        XCTAssertEqual(fixture.viewModel.messageQueue.pending.map(\.text), ["Fast queued"])
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }
}

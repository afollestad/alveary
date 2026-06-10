import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testQueueOrSendWhileBusyCapturesStagedContextAndClearsLiveBanner() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.stagedContext = "Context block"
        fixture.viewModel.turnState.beginTurn()

        try await fixture.viewModel.queueOrSend("Follow-up")

        let queued = try XCTUnwrap(fixture.viewModel.messageQueue.peekNext())
        XCTAssertEqual(queued.text, "Follow-up")
        XCTAssertEqual(queued.stagedContext, "Context block")
        XCTAssertNil(fixture.viewModel.state.stagedContext)
    }

    func testQueuedPlanModeIntentDoesNotAffectOlderQueuedMessages() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true
        )
        fixture.viewModel.activateViewLifecycle()
        fixture.viewModel.state.runtimePlanModeEnabled = false
        fixture.viewModel.turnState.beginTurn()

        try await fixture.viewModel.queueOrSend("Older queued")
        try await fixture.viewModel.queueOrSend("Plan queued", requiredPlanModeEnabled: true)

        XCTAssertEqual(fixture.viewModel.messageQueue.pending.map(\.text), ["Older queued", "Plan queued"])
        XCTAssertEqual(fixture.viewModel.messageQueue.pending.map(\.requiredPlanModeEnabled), [nil, true])

        fixture.viewModel.turnState.endTurn()
        fixture.viewModel.handleTurnCompleted()

        try await waitUntil("older queued message sent first") {
            await fixture.agentsManager.sentMessages() == ["Older queued"]
        }
        let reconfigureCallsBeforePlan = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCallsBeforePlan.isEmpty)

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

        try await waitUntil("plan queued message sent") {
            await fixture.agentsManager.sentMessages() == ["Older queued", "Plan queued"]
        }
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(reconfigureCalls.count, 1)
        XCTAssertEqual(reconfigureCalls.first?.config.planModeEnabled, true)
    }

    func testQueuedPlanModeDisableIntentDoesNotAffectOlderQueuedMessages() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true
        )
        fixture.viewModel.activateViewLifecycle()
        fixture.viewModel.state.runtimePlanModeEnabled = true
        fixture.viewModel.turnState.beginTurn()

        try await fixture.viewModel.queueOrSend("Older queued")
        try await fixture.viewModel.queueOrSend("Plan-off queued", requiredPlanModeEnabled: false)

        XCTAssertEqual(fixture.viewModel.messageQueue.pending.map(\.text), ["Older queued", "Plan-off queued"])
        XCTAssertEqual(fixture.viewModel.messageQueue.pending.map(\.requiredPlanModeEnabled), [nil, false])

        fixture.viewModel.turnState.endTurn()
        fixture.viewModel.handleTurnCompleted()

        try await waitUntil("older queued message sent first") {
            await fixture.agentsManager.sentMessages() == ["Older queued"]
        }
        let reconfigureCallsBeforePlanToggle = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCallsBeforePlanToggle.isEmpty)

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

        try await waitUntil("plan-off queued message sent") {
            await fixture.agentsManager.sentMessages() == ["Older queued", "Plan-off queued"]
        }
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(reconfigureCalls.count, 1)
        XCTAssertEqual(reconfigureCalls.first?.config.planModeEnabled, false)
    }

    func testQueueOrSendWhileRuntimeBusyQueuesWithoutSendingImmediately() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.setStatus(.busy, for: fixture.conversation.id)
        fixture.viewModel.state.stagedContext = "Runtime context"

        try await fixture.viewModel.queueOrSend("Follow-up")

        let queued = try XCTUnwrap(fixture.viewModel.messageQueue.peekNext())
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(queued.text, "Follow-up")
        XCTAssertEqual(queued.stagedContext, "Runtime context")
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertNil(fixture.viewModel.state.stagedContext)
    }

    func testSteerWhileRuntimeBusyDoesNotRequireLocalTurnState() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.setStatus(.busy, for: fixture.conversation.id)

        try await fixture.viewModel.steer("Steer now")

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, ["Steer now"])
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Steer now"])
        XCTAssertTrue(fixture.viewModel.turnState.isActive)
    }

    func testSteerWithoutActiveTurnReturnsReadableError() async throws {
        let fixture = try ConversationViewModelTestFixture()

        do {
            try await fixture.viewModel.steer("Too soon")
            XCTFail("Expected steer to fail without an active turn")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Wait for the agent to be actively working before steering")
        }
    }

    func testCodexSteerRequiresRuntimeActivityTurnId() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        await fixture.agentsManager.setStatus(.busy, for: fixture.conversation.id)

        do {
            try await fixture.viewModel.steer("Too soon")
            XCTFail("Expected Codex steer to fail before the runtime reports a steerable turn")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Wait for the agent to be actively working before steering")
        }

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
    }

    func testCodexSteerSucceedsAfterRuntimeActivityTurnId() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.activeRuntimeActivityTurnId = "turn-1"

        try await fixture.viewModel.steer("Steer now")

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, ["Steer now"])
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Steer now"])
        XCTAssertTrue(fixture.viewModel.turnState.isActive)
    }

    func testCancelWhileRuntimeBusyDoesNotRequireLocalTurnState() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.setStatus(.busy, for: fixture.conversation.id)

        await fixture.viewModel.cancel()

        let cancelCalls = await fixture.agentsManager.cancelCalls()
        XCTAssertEqual(cancelCalls, [fixture.conversation.id])
        XCTAssertTrue(fixture.viewModel.state.isCancellingTurn)
    }

    func testQueueOrSendWhileRuntimeIdleSendsImmediately() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.setStatus(.idle, for: fixture.conversation.id)

        try await fixture.viewModel.queueOrSend("Send now")

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertNil(fixture.viewModel.messageQueue.peekNext())
        XCTAssertEqual(sentMessages, ["Send now"])
        XCTAssertTrue(fixture.viewModel.turnState.isActive)
    }

    func testQueuedMessageDrainsAfterStaleBusyStatusRefreshesIdle() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.activateViewLifecycle()
        await fixture.agentsManager.setStatus(.busy, for: fixture.conversation.id)
        await fixture.agentsManager.enqueueRefreshStatus(.idle)
        fixture.viewModel.turnState.beginTurn()

        try await fixture.viewModel.queueOrSend("Follow-up")
        fixture.viewModel.handleTurnCompleted()

        try await waitUntil("queued message sent after stale busy refresh") {
            await fixture.agentsManager.sentMessages() == ["Follow-up"] &&
                fixture.viewModel.messageQueue.peekNext() == nil
        }
        let refreshStatusCalls = await fixture.agentsManager.refreshStatusCalls()
        XCTAssertEqual(refreshStatusCalls, [fixture.conversation.id])
        XCTAssertTrue(fixture.viewModel.turnState.isActive)
    }

    func testQueuedMessageDrainsAfterPostEnqueueStaleBusyRefreshesIdle() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.activateViewLifecycle()
        await fixture.agentsManager.setStatus(.busy, for: fixture.conversation.id)
        await fixture.agentsManager.enqueueRefreshStatus(.idle)

        try await fixture.viewModel.queueOrSend("Follow-up")

        try await waitUntil("queued message sent after post-enqueue stale busy refresh") {
            await fixture.agentsManager.sentMessages() == ["Follow-up"] &&
                fixture.viewModel.messageQueue.peekNext() == nil
        }
        let refreshStatusCalls = await fixture.agentsManager.refreshStatusCalls()
        XCTAssertEqual(refreshStatusCalls, [fixture.conversation.id])
        XCTAssertTrue(fixture.viewModel.turnState.isActive)
    }

    func testQueuedMessageDoesNotDrainUntilViewLifecycleActivates() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.turnState.beginTurn()

        try await fixture.viewModel.queueOrSend("Follow-up")
        fixture.viewModel.handleTurnCompleted()
        try await Task.sleep(nanoseconds: 50_000_000)

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, [])
        XCTAssertEqual(fixture.viewModel.messageQueue.peekNext()?.text, "Follow-up")

        fixture.viewModel.activateViewLifecycle()

        try await waitUntil("queued message sent after activation") {
            await fixture.agentsManager.sentMessages() == ["Follow-up"] &&
                fixture.viewModel.messageQueue.peekNext() == nil
        }
    }

    func testQueuedMessageDoesNotDrainWhenLifecycleDeactivatesDuringStatusRefresh() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.activateViewLifecycle()
        await fixture.agentsManager.setStatus(.busy, for: fixture.conversation.id)
        await fixture.agentsManager.enqueueRefreshStatus(.idle)
        await fixture.agentsManager.pauseNextRefreshStatus()
        fixture.viewModel.turnState.beginTurn()

        try await fixture.viewModel.queueOrSend("Follow-up")
        fixture.viewModel.handleTurnCompleted()

        try await waitUntil("status refresh starts before lifecycle deactivation") {
            await fixture.agentsManager.refreshStatusCalls() == [fixture.conversation.id]
        }

        fixture.viewModel.deactivateViewLifecycle()
        await fixture.agentsManager.resumePausedRefreshStatus()
        try await Task.sleep(nanoseconds: 50_000_000)

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, [])
        XCTAssertEqual(fixture.viewModel.messageQueue.peekNext()?.text, "Follow-up")
    }

    func testQueuedMessageFailureMovesRetryToTranscriptMessage() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.activateViewLifecycle()
        fixture.viewModel.state.stagedContext = "Context block"
        fixture.viewModel.turnState.beginTurn()

        try await fixture.viewModel.queueOrSend("Follow-up")
        await fixture.agentsManager.enqueueSendResult(.failure(.sendFailed))

        fixture.viewModel.handleTurnCompleted()

        try await waitUntil("queued send failure recorded on transcript message") {
            let userMessages = try fixture.userMessages()
            guard let userMessage = userMessages.first else {
                return false
            }

            return fixture.viewModel.messageQueue.peekNext() == nil
                && fixture.viewModel.state.retryableFailedMessageIDs.contains(userMessage.id)
                && fixture.viewModel.lastTurnError?.hasPrefix("Queued message failed to send:") == true
        }

        let failedMessage = try XCTUnwrap(try fixture.userMessages().first)
        XCTAssertEqual(failedMessage.content, "Follow-up")
        XCTAssertEqual(fixture.viewModel.state.retryableFailedMessageStagedContexts[failedMessage.id], "Context block")
        XCTAssertTrue(fixture.viewModel.lastTurnError?.hasPrefix("Queued message failed to send:") == true)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)

        try await fixture.viewModel.retryFailedUserMessage(id: failedMessage.id)

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Follow-up"])
        XCTAssertEqual(sentMessages, ["Context block\n\nFollow-up"])
        XCTAssertFalse(fixture.viewModel.state.retryableFailedMessageIDs.contains(failedMessage.id))
        XCTAssertNil(fixture.viewModel.state.retryableFailedMessageStagedContexts[failedMessage.id])
        XCTAssertNil(fixture.viewModel.lastTurnError)
    }

    func testQueuedMessageSendsAfterPermissionDeniedTurnCompletes() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.activateViewLifecycle()
        fixture.viewModel.turnState.beginTurn()

        try await fixture.viewModel.queueOrSend("Follow-up")

        fixture.viewModel.handleEvent(
            .tokens(
                input: 1,
                output: 1,
                cacheRead: 0,
                isError: true,
                stopReason: "tool_use",
                durationMs: 10,
                costUsd: 0,
                permissionDenials: [PermissionDenialSummary(toolName: "Bash", toolUseId: "tool-1")]
            )
        )

        try await waitUntil("queued message sent after permission denial") {
            let sentMessages = await fixture.agentsManager.sentMessages()
            return sentMessages == ["Follow-up"]
                && fixture.viewModel.messageQueue.peekNext() == nil
        }

        XCTAssertTrue(fixture.viewModel.turnState.isActive)
        XCTAssertFalse(fixture.viewModel.state.lastTurnInterrupted)
        XCTAssertFalse(fixture.viewModel.state.isCancellingTurn)
        XCTAssertNil(fixture.viewModel.lastTurnError)
    }

    func testSteerQueuedMessageCanSendAnyQueuedEntryImmediately() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.turnState.beginTurn()

        fixture.viewModel.state.stagedContext = "First context"
        try await fixture.viewModel.queueOrSend("First queued")
        fixture.viewModel.state.stagedContext = "Second context"
        try await fixture.viewModel.queueOrSend("Second queued")
        fixture.viewModel.state.stagedContext = nil
        try await fixture.viewModel.queueOrSend("Third queued")

        XCTAssertGreaterThan(fixture.viewModel.messageQueue.pending.count, 1)
        let secondQueuedID = fixture.viewModel.messageQueue.pending[1].id

        try await fixture.viewModel.steerQueuedMessage(id: secondQueuedID)

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, ["Second context\n\nSecond queued"])
        XCTAssertEqual(fixture.viewModel.messageQueue.pending.map(\.text), ["First queued", "Third queued"])
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Second queued"])
        XCTAssertNil(fixture.viewModel.state.inFlightQueuedMessageID)
    }

    func testSteerQueuedMessageWhileRuntimeBusyDoesNotRequireLocalTurnState() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.stagedContext = "Queued context"
        fixture.viewModel.turnState.beginTurn()
        try await fixture.viewModel.queueOrSend("Queued steer")
        fixture.viewModel.turnState.endTurn()
        await fixture.agentsManager.setStatus(.busy, for: fixture.conversation.id)

        let queuedID = try XCTUnwrap(fixture.viewModel.messageQueue.peekNext()?.id)
        try await fixture.viewModel.steerQueuedMessage(id: queuedID)

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, ["Queued context\n\nQueued steer"])
        XCTAssertTrue(fixture.viewModel.messageQueue.pending.isEmpty)
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Queued steer"])
        XCTAssertTrue(fixture.viewModel.turnState.isActive)
        XCTAssertNil(fixture.viewModel.state.inFlightQueuedMessageID)
    }

    func testSteerQueuedMessageRejectsPlanModeIntent() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.turnState.beginTurn()
        try await fixture.viewModel.queueOrSend("Plan queued", requiredPlanModeEnabled: true)

        let queuedID = try XCTUnwrap(fixture.viewModel.messageQueue.peekNext()?.id)
        do {
            try await fixture.viewModel.steerQueuedMessage(id: queuedID)
            XCTFail("Expected plan-mode queued message steering to fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Plan-mode queued messages send on the next turn")
        }

        XCTAssertEqual(fixture.viewModel.messageQueue.pending.map(\.text), ["Plan queued"])
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testCodexSteerQueuedMessageRequiresRuntimeActivityTurnId() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        fixture.viewModel.state.stagedContext = "Queued context"
        fixture.viewModel.turnState.beginTurn()
        try await fixture.viewModel.queueOrSend("Queued steer")
        fixture.viewModel.turnState.endTurn()
        await fixture.agentsManager.setStatus(.busy, for: fixture.conversation.id)

        let queuedID = try XCTUnwrap(fixture.viewModel.messageQueue.peekNext()?.id)
        do {
            try await fixture.viewModel.steerQueuedMessage(id: queuedID)
            XCTFail("Expected Codex queued steer to fail before the runtime reports a steerable turn")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Wait for the agent to be actively working before steering")
        }

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertEqual(fixture.viewModel.messageQueue.pending.map(\.text), ["Queued steer"])
        XCTAssertNil(fixture.viewModel.state.inFlightQueuedMessageID)
    }
}

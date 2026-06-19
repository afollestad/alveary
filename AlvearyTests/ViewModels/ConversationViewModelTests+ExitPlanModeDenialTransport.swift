import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testPlainClaudeDenyWrapsNextNormalFeedbackWithoutChangingVisibleTranscript() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false, providerId: "claude")
        try enablePlanMode(for: fixture)
        let approval = exitPlanModeTransportApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.denyExitPlanMode(toolUseId: approval.toolUseId)

        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(calls.first?.resolution.responseText, ExitPlanModeDenialPolicy.deniedResponseText)
        XCTAssertNotNil(fixture.viewModel.state.pendingExitPlanModeRevisionGuidance)

        try await fixture.viewModel.queueOrSend("Add a lorem ipsum line to the top of the proposal")

        let expectedTransport = exitPlanModeRevisionTransportText("Add a lorem ipsum line to the top of the proposal")
        try await waitUntil("plain Claude plan feedback sent with wrapped transport") {
            await fixture.agentsManager.sentMessages() == [expectedTransport]
        }
        XCTAssertEqual(
            try fixture.userMessages().map(\.content),
            ["Add a lorem ipsum line to the top of the proposal"]
        )
        XCTAssertNil(fixture.viewModel.state.pendingExitPlanModeRevisionGuidance)
    }

    func testPlainCodexDenyDoesNotWrapNextNormalFeedback() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false, providerId: "codex")
        try enablePlanMode(for: fixture)
        let approval = exitPlanModeTransportApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.denyExitPlanMode(toolUseId: approval.toolUseId)

        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(calls.first?.resolution.responseText, ExitPlanModeDenialPolicy.deniedResponseText)
        XCTAssertNil(fixture.viewModel.state.pendingExitPlanModeRevisionGuidance)

        try await fixture.viewModel.queueOrSend("Add a lorem ipsum line to the top of the proposal")

        try await waitUntil("plain Codex plan feedback sent raw") {
            await fixture.agentsManager.sentMessages() == ["Add a lorem ipsum line to the top of the proposal"]
        }
        XCTAssertEqual(
            try fixture.userMessages().map(\.content),
            ["Add a lorem ipsum line to the top of the proposal"]
        )
    }

    func testCustomClaudeDenyFollowUpUsesWrappedTransportWhenPlanModeEnabled() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false, providerId: "claude")
        try enablePlanMode(for: fixture)
        let approval = exitPlanModeTransportApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.denyExitPlanMode(
            toolUseId: approval.toolUseId,
            followUp: "Please revise the plan first."
        )

        fixture.viewModel.handleEvent(exitPlanModeTransportTerminalToken(for: approval))

        try await waitUntil("custom Claude plan feedback sent with wrapped transport") {
            await fixture.agentsManager.sentMessages() == [exitPlanModeRevisionTransportFollowUp()]
        }
        XCTAssertEqual(
            try fixture.userMessages().map(\.content),
            [exitPlanModeTransportRevisionFollowUp()]
        )
    }

    func testPlainClaudeRevisionTransportIsPreservedForRetry() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true, providerId: "claude")
        try enablePlanMode(for: fixture)
        let approval = exitPlanModeTransportApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
        await fixture.agentsManager.enqueueSendResult(.failure(.sendFailed))

        try await fixture.viewModel.denyExitPlanMode(toolUseId: approval.toolUseId)

        do {
            try await fixture.viewModel.queueOrSend("Please revise this.")
            XCTFail("Expected send failure")
        } catch let error as MockAgentsManager.MockError {
            XCTAssertEqual(error, .sendFailed)
        }

        let failedMessage = try XCTUnwrap(try fixture.userMessages().first)
        let expectedTransport = exitPlanModeRevisionTransportText("Please revise this.")
        XCTAssertEqual(failedMessage.content, "Please revise this.")
        XCTAssertEqual(fixture.viewModel.state.retryableFailedMessageTransportTexts[failedMessage.id], expectedTransport)

        try await fixture.viewModel.retryFailedUserMessage(id: failedMessage.id)

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, [expectedTransport])
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Please revise this."])
        XCTAssertNil(fixture.viewModel.state.retryableFailedMessageTransportTexts[failedMessage.id])
    }

    func testPlainClaudeRevisionTransportIsPreservedAcrossStdinClosedRespawnRecovery() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true, providerId: "claude")
        try enablePlanMode(for: fixture)
        let approval = exitPlanModeTransportApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
        await fixture.agentsManager.enqueueOutboundReadiness(.ready)
        await fixture.agentsManager.enqueueOutboundReadiness(.respawnRequired)
        await fixture.agentsManager.enqueueSendResult(.failure(.stdinClosed))

        try await fixture.viewModel.denyExitPlanMode(toolUseId: approval.toolUseId)
        try await fixture.viewModel.queueOrSend("Please revise this.")

        let expectedTransport = exitPlanModeRevisionTransportText("Please revise this.")
        let sentMessages = await fixture.agentsManager.sentMessages()
        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertEqual(sentMessages, [expectedTransport])
        XCTAssertEqual(spawnCalls.count, 1)
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Please revise this."])
    }

    func testPlainClaudeRevisionTransportIsUsedForInitialSetupOnly() async throws {
        let worktreeInfo = WorktreeInfo(path: "/tmp/alveary-worktree", branch: "alveary/revise-plan")
        let fixture = try ConversationViewModelTestFixture(
            threadName: "New thread",
            useWorktree: true,
            hasCompletedInitialSetup: false,
            worktreeInfo: worktreeInfo,
            initialAgentIsRunning: false,
            providerId: "claude"
        )
        try enablePlanMode(for: fixture)
        let approval = exitPlanModeTransportApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.denyExitPlanMode(toolUseId: approval.toolUseId)
        try await fixture.viewModel.queueOrSend("Please revise this.")

        let expectedTransport = exitPlanModeRevisionTransportText("Please revise this.")
        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertEqual(spawnCalls.first?.config.initialPrompt, expectedTransport)
        let createCalls = await fixture.worktreeManager.createCalls()
        XCTAssertEqual(createCalls.first?.threadName, "Please revise this.")
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Please revise this."])
    }

    func testPlainClaudeRevisionGuidanceRearmsAfterInitialSetupCancellationRollback() async throws {
        let fixture = try ConversationViewModelTestFixture(
            threadName: "New thread",
            useWorktree: true,
            hasCompletedInitialSetup: false,
            pausesWorktreeCreate: true,
            initialAgentIsRunning: false,
            providerId: "claude"
        )
        try enablePlanMode(for: fixture)
        let approval = exitPlanModeTransportApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.denyExitPlanMode(toolUseId: approval.toolUseId)
        let sendTask = Task {
            try await fixture.viewModel.queueOrSend("Please revise this.")
        }

        for _ in 0..<50 where fixture.viewModel.setupPhase == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(fixture.viewModel.setupPhase, .creatingWorktree)
        XCTAssertNil(fixture.viewModel.state.pendingExitPlanModeRevisionGuidance)

        await fixture.viewModel.cancel()

        do {
            try await sendTask.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // expected
        }

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Please revise this.")
        XCTAssertTrue(try fixture.userMessages().isEmpty)
        XCTAssertNotNil(fixture.viewModel.state.pendingExitPlanModeRevisionGuidance)

        let outbound = fixture.viewModel.preparedNormalUserOutboundText("Please revise after cancel.")
        XCTAssertEqual(outbound.visibleText, "Please revise after cancel.")
        XCTAssertEqual(outbound.transportText, exitPlanModeRevisionTransportText("Please revise after cancel."))
    }

    func testPlainClaudeRevisionGuidanceClearsOnProviderMismatch() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false, providerId: "claude")
        try enablePlanMode(for: fixture)
        let approval = exitPlanModeTransportApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.denyExitPlanMode(toolUseId: approval.toolUseId)
        let conversation = try fixture.dbConversation()
        conversation.provider = "codex"
        try fixture.context.save()
        try await fixture.viewModel.queueOrSend("Please revise this.")

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, ["Please revise this."])
        XCTAssertNil(fixture.viewModel.state.pendingExitPlanModeRevisionGuidance)
    }

    func testPlainClaudeRevisionGuidanceClearsOnProviderSessionMismatch() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false, providerId: "claude")
        try enablePlanMode(for: fixture)
        let conversation = try fixture.dbConversation()
        conversation.providerSessionProviderId = "claude"
        conversation.providerSessionId = "session-a"
        try fixture.context.save()
        let approval = exitPlanModeTransportApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.denyExitPlanMode(toolUseId: approval.toolUseId)
        conversation.providerSessionId = "session-b"
        try fixture.context.save()
        try await fixture.viewModel.queueOrSend("Please revise this.")

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, ["Please revise this."])
        XCTAssertNil(fixture.viewModel.state.pendingExitPlanModeRevisionGuidance)
    }

    func testQueuedPlanRevisionFeedbackCannotBeSteeredAndEditRearmsGuidance() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true, providerId: "claude")
        try enablePlanMode(for: fixture)
        let approval = exitPlanModeTransportApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.denyExitPlanMode(toolUseId: approval.toolUseId)
        fixture.viewModel.state.turnState.beginTurn()

        try await fixture.viewModel.queueOrSend("Please revise this.")

        let queued = try XCTUnwrap(fixture.viewModel.state.messageQueue.peekNext())
        XCTAssertEqual(queued.text, "Please revise this.")
        XCTAssertEqual(queued.transportText, exitPlanModeRevisionTransportText("Please revise this."))
        XCTAssertEqual(queued.requiredPlanModeEnabled, true)
        XCTAssertNotNil(queued.consumedExitPlanModeRevisionGuidance)

        do {
            try await fixture.viewModel.steerQueuedMessage(id: queued.id)
            XCTFail("Expected transport-only queued plan feedback to be rejected for steering")
        } catch {}

        fixture.viewModel.editQueuedMessage(id: queued.id)

        XCTAssertTrue(fixture.viewModel.state.messageQueue.pending.isEmpty)
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Please revise this.")
        XCTAssertNotNil(fixture.viewModel.state.pendingExitPlanModeRevisionGuidance)
    }

    func testQueuedPlanRevisionFeedbackSendsRawWhenPlanModeTurnsOffBeforeDrain() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true, providerId: "claude")
        fixture.viewModel.activateViewLifecycle()
        try enablePlanMode(for: fixture)
        let approval = exitPlanModeTransportApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.denyExitPlanMode(toolUseId: approval.toolUseId)
        fixture.viewModel.state.turnState.beginTurn()
        try await fixture.viewModel.queueOrSend("Please revise this.")

        let queued = try XCTUnwrap(fixture.viewModel.state.messageQueue.peekNext())
        XCTAssertEqual(queued.transportText, exitPlanModeRevisionTransportText("Please revise this."))

        fixture.viewModel.syncRuntimePlanMode(false)
        fixture.viewModel.state.turnState.endTurn()
        fixture.viewModel.handleTurnCompleted()

        try await waitUntil("stale queued plan feedback sent raw") {
            await fixture.agentsManager.sentMessages() == ["Please revise this."]
        }
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testPlainClaudeRevisionGuidanceRearmsWhenPreflightSettingsApplyFails() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            reconfigureError: .reconfigureFailed,
            initialAgentIsRunning: true,
            providerId: "claude",
        )
        try enablePlanMode(for: fixture)
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.applyEffortChange("high")
        fixture.viewModel.state.turnState.endTurn()
        let approval = exitPlanModeTransportApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.denyExitPlanMode(toolUseId: approval.toolUseId)
        XCTAssertNotNil(fixture.viewModel.state.pendingExitPlanModeRevisionGuidance)

        do {
            try await fixture.viewModel.queueOrSend("Please revise this.")
            XCTFail("Expected staged settings apply to fail before sending")
        } catch let error as MockAgentsManager.MockError {
            XCTAssertEqual(error, .reconfigureFailed)
        }

        XCTAssertNotNil(fixture.viewModel.state.pendingExitPlanModeRevisionGuidance)
        XCTAssertTrue(try fixture.userMessages().isEmpty)
        XCTAssertTrue(fixture.viewModel.state.retryableFailedMessageIDs.isEmpty)
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testQueuedCustomPlanFollowUpSendsRawWhenPlanModeTurnsOffBeforeDrain() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true, providerId: "claude")
        fixture.viewModel.activateViewLifecycle()
        fixture.viewModel.deactivateViewLifecycle()
        try enablePlanMode(for: fixture)
        let approval = exitPlanModeTransportApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.denyExitPlanMode(
            toolUseId: approval.toolUseId,
            followUp: "Please revise the plan first."
        )
        XCTAssertTrue(fixture.viewModel.markPendingExitPlanModeFollowUpReadyAfterTerminalBoundary(
            toolUseId: approval.toolUseId,
            sessionId: approval.sessionId
        ))

        let queued = try XCTUnwrap(fixture.viewModel.state.messageQueue.peekNext())
        XCTAssertEqual(queued.transportText, exitPlanModeRevisionTransportFollowUp())
        XCTAssertNotNil(queued.consumedExitPlanModeRevisionGuidance)

        fixture.viewModel.syncRuntimePlanMode(false)
        fixture.viewModel.activateViewLifecycle()

        try await waitUntil("stale custom plan feedback sent raw") {
            await fixture.agentsManager.sentMessages() == [exitPlanModeTransportRevisionFollowUp()]
        }
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testSessionHandoffClearsQueuedRevisionTransportBeforeHiddenPrompt() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true, providerId: "claude")
        try enablePlanMode(for: fixture)
        let approval = exitPlanModeTransportApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.denyExitPlanMode(toolUseId: approval.toolUseId)
        fixture.viewModel.state.turnState.beginTurn()
        try await fixture.viewModel.queueOrSend("Please revise this.")

        let queuedBeforeHandoff = try XCTUnwrap(fixture.viewModel.state.messageQueue.peekNext())
        XCTAssertEqual(queuedBeforeHandoff.transportText, exitPlanModeRevisionTransportText("Please revise this."))

        fixture.viewModel.state.turnState.endTurn()
        await fixture.viewModel.startSessionHandoff(trigger: .manual)

        try await waitUntil("hidden session handoff prompt sent raw") {
            await fixture.agentsManager.sentMessages() == [AppSettings.defaultSessionHandoffPrompt]
        }
        let queuedAfterHandoff = try XCTUnwrap(fixture.viewModel.state.messageQueue.peekNext())
        XCTAssertEqual(queuedAfterHandoff.id, queuedBeforeHandoff.id)
        XCTAssertEqual(queuedAfterHandoff.text, "Please revise this.")
        XCTAssertNil(queuedAfterHandoff.transportText)
        XCTAssertNil(queuedAfterHandoff.consumedExitPlanModeRevisionGuidance)
        XCTAssertNil(queuedAfterHandoff.requiredPlanModeEnabled)
        XCTAssertNil(fixture.viewModel.state.pendingExitPlanModeRevisionGuidance)
    }
}

private func exitPlanModeTransportApproval(toolUseId: String) -> ToolApprovalRequest {
    ToolApprovalRequest(
        sessionId: "session-123",
        toolUseId: toolUseId,
        toolName: "ExitPlanMode",
        toolInput: ##"{"plan":"# Plan\n\n- Do the work."}"##
    )
}

private func exitPlanModeTransportRevisionFollowUp(_ feedback: String = "Please revise the plan first.") -> String {
    ConversationViewModel.exitPlanModeRevisionFollowUpPrompt(feedback: feedback)
}

private func exitPlanModeRevisionTransportFollowUp(_ feedback: String = "Please revise the plan first.") -> String {
    exitPlanModeRevisionTransportText(exitPlanModeTransportRevisionFollowUp(feedback))
}

private func exitPlanModeRevisionTransportText(_ visibleText: String) -> String {
    ExitPlanModeDenialPolicy.revisionTransportText(visibleText: visibleText)
}

private func exitPlanModeTransportTerminalToken(for approval: ToolApprovalRequest) -> ConversationEvent {
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

@MainActor
private func enablePlanMode(for fixture: ConversationViewModelTestFixture) throws {
    try fixture.dbThread().planModeEnabled = true
    fixture.viewModel.state.runtimePlanModeEnabled = true
    try fixture.context.save()
}

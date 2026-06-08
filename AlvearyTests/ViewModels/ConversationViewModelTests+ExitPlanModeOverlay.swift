import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testApproveExitPlanModeRoutesAllowDecisionForClaude() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false, providerId: "claude")
        let approval = exitPlanModeApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.approveExitPlanMode(toolUseId: approval.toolUseId)

        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.decision, .allow)
        XCTAssertEqual(calls.first?.approval, approval)
        XCTAssertEqual(calls.first?.config.providerId, "claude")
        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.status, .approving)
    }

    func testDismissExitPlanModeRoutesDenyDecisionForCodex() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false, providerId: "codex")
        let approval = exitPlanModeApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.denyExitPlanMode(toolUseId: approval.toolUseId)

        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.decision, .deny)
        XCTAssertEqual(calls.first?.approval, approval)
        XCTAssertEqual(calls.first?.config.providerId, "codex")
        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertFalse(fixture.viewModel.state.turnState.isActive)
        XCTAssertNil(fixture.viewModel.state.pendingExitPlanModeFollowUp)
    }

    func testCustomDenyFollowUpWaitsForApprovalClearThenSendsBeforeOlderQueuedMessages() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let conversation = try fixture.dbConversation()
        let approval = exitPlanModeApproval(toolUseId: "exit-plan-1")
        let approvalRecord = exitPlanModeApprovalRecord(conversation: conversation, approval: approval)
        fixture.context.insert(approvalRecord)
        try fixture.context.save()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
        fixture.viewModel.state.messageQueue.enqueue("Older queued message", stagedContext: "Queued context")
        fixture.viewModel.state.stagedContext = "Live staged context"

        try await fixture.viewModel.denyExitPlanMode(
            toolUseId: approval.toolUseId,
            followUp: "  Please revise the plan first.  "
        )

        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertEqual(fixture.viewModel.state.pendingExitPlanModeFollowUp?.phase, .awaitingDeniedExitTurn)
        XCTAssertTrue(fixture.viewModel.state.isAwaitingExitPlanModeFollowUp)
        XCTAssertEqual(fixture.viewModel.state.messageQueue.pending.map(\.text), ["Older queued message"])
        XCTAssertEqual(fixture.viewModel.state.messageQueue.pending.first?.stagedContext, "Queued context")
        XCTAssertTrue(try fixture.userMessages().isEmpty)
        var sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)

        let denialAcknowledgement = "Plan mode test complete. User denied exit - plan stays open."
        fixture.viewModel.handleEvent(.message(role: "assistant", content: denialAcknowledgement, parentToolUseId: nil))

        sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)

        fixture.viewModel.handleEvent(exitPlanModeTerminalToken(for: approval))

        try await waitUntil("custom plan follow-up sent after denied-turn terminal token") {
            await fixture.agentsManager.sentMessages() == ["Please revise the plan first."]
        }

        let records = try conversationRecords(for: fixture)
        let acknowledgementIndex = try XCTUnwrap(records.firstIndex {
            $0.role == "assistant" && $0.content == denialAcknowledgement
        })
        let followUpIndex = try XCTUnwrap(records.firstIndex {
            $0.role == "user" && $0.content == "Please revise the plan first."
        })
        XCTAssertLessThan(acknowledgementIndex, followUpIndex)
        XCTAssertNil(fixture.viewModel.state.pendingExitPlanModeFollowUp)
        XCTAssertEqual(fixture.viewModel.state.stagedContext, "Live staged context")
        XCTAssertEqual(approvalRecord.toolApprovalStatus, ToolApprovalStatus.denied.rawValue)
    }

    func testExitPlanModeToolResultAloneDoesNotDrainCustomDenyFollowUp() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        let approval = exitPlanModeApproval(toolUseId: "exit-plan-1")
        await fixture.agentsManager.enableSubscription()
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
        fixture.viewModel.subscribe()
        try await waitUntil("subscription becomes active", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            await fixture.agentsManager.hasActiveSubscription()
        }

        try await fixture.viewModel.denyExitPlanMode(
            toolUseId: approval.toolUseId,
            followUp: "Please revise the plan first."
        )

        await fixture.agentsManager.yieldSubscriptionEvent(.toolResult(
            id: approval.toolUseId,
            output: "User denied ExitPlanMode.",
            isError: true,
            parentToolUseId: nil,
            metadata: nil
        ))
        try await Task.sleep(for: .milliseconds(900))

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertEqual(fixture.viewModel.state.pendingExitPlanModeFollowUp?.phase, .awaitingDeniedExitTurn)
    }

    func testCustomDenyFollowUpDrainsAfterMatchingRuntimeIdle() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        let approval = exitPlanModeApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.activeRuntimeActivityTurnId = "turn-1"
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
        fixture.viewModel.state.messageQueue.enqueue("Older queued message", stagedContext: "Queued context")

        try await fixture.viewModel.denyExitPlanMode(
            toolUseId: approval.toolUseId,
            followUp: "Please revise the plan first."
        )

        fixture.viewModel.handleEvent(.runtimeActivity(state: .idle, turnId: "turn-other", outcome: .completed))

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertEqual(fixture.viewModel.state.pendingExitPlanModeFollowUp?.phase, .awaitingDeniedExitTurn)
        XCTAssertEqual(fixture.viewModel.state.messageQueue.pending.map(\.text), ["Older queued message"])
        XCTAssertNil(fixture.viewModel.state.lastTurnError)

        fixture.viewModel.handleEvent(.runtimeActivity(state: .idle, turnId: "turn-1", outcome: .completed))

        try await waitUntil("custom plan follow-up sent after matching runtime idle") {
            await fixture.agentsManager.sentMessages() == ["Please revise the plan first."]
        }
        XCTAssertNil(fixture.viewModel.state.pendingExitPlanModeFollowUp)
    }

    func testCustomDenyFollowUpDrainsAfterSubscriptionFinishes() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        let approval = exitPlanModeApproval(toolUseId: "exit-plan-1")
        await fixture.agentsManager.enableSubscription()
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
        fixture.viewModel.subscribe()
        try await waitUntil("subscription becomes active", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            await fixture.agentsManager.hasActiveSubscription()
        }

        try await fixture.viewModel.denyExitPlanMode(
            toolUseId: approval.toolUseId,
            followUp: "Please revise the plan first."
        )

        await fixture.agentsManager.finishSubscription()

        try await waitUntil("custom plan follow-up sent after subscription finish") {
            await fixture.agentsManager.sentMessages() == ["Please revise the plan first."]
        }
        XCTAssertNil(fixture.viewModel.state.pendingExitPlanModeFollowUp)
    }

    func testViewDeactivationDoesNotDrainCustomDenyFollowUp() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        let approval = exitPlanModeApproval(toolUseId: "exit-plan-1")
        await fixture.agentsManager.enableSubscription()
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
        fixture.viewModel.activateViewLifecycle()
        try await waitUntil("subscription becomes active", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            await fixture.agentsManager.hasActiveSubscription()
        }

        try await fixture.viewModel.denyExitPlanMode(
            toolUseId: approval.toolUseId,
            followUp: "Please revise the plan first."
        )

        fixture.viewModel.deactivateViewLifecycle()
        await fixture.agentsManager.finishSubscription()
        try await Task.sleep(for: .milliseconds(900))

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertEqual(fixture.viewModel.state.pendingExitPlanModeFollowUp?.phase, .awaitingDeniedExitTurn)
    }

    func testManualSendIsBlockedWhileCustomDenyFollowUpAwaitsDrain() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let approval = exitPlanModeApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.denyExitPlanMode(
            toolUseId: approval.toolUseId,
            followUp: "Please revise the plan first."
        )

        do {
            try await fixture.viewModel.queueOrSend("Manual message")
            XCTFail("Expected manual send to be blocked")
        } catch {}

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertTrue(fixture.viewModel.state.messageQueue.pending.isEmpty)
    }

    func testCustomDenyFollowUpUsesQueuedMessageRetryBehaviorOnSendFailure() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let approval = exitPlanModeApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
        await fixture.agentsManager.enqueueSendResult(.failure(.sendFailed))

        try await fixture.viewModel.denyExitPlanMode(
            toolUseId: approval.toolUseId,
            followUp: "Please revise the plan first."
        )

        fixture.viewModel.handleEvent(exitPlanModeTerminalToken(for: approval))

        try await waitUntil("custom plan follow-up failure recorded on transcript message") {
            let userMessages = try fixture.userMessages()
            guard let userMessage = userMessages.first else {
                return false
            }

            return fixture.viewModel.state.retryableFailedMessageIDs.contains(userMessage.id)
                && fixture.viewModel.lastTurnError?.hasPrefix("Queued message failed to send:") == true
        }

        let failedMessage = try XCTUnwrap(try fixture.userMessages().first)
        XCTAssertEqual(failedMessage.content, "Please revise the plan first.")
        XCTAssertNil(fixture.viewModel.state.retryableFailedMessageStagedContexts[failedMessage.id])

        try await fixture.viewModel.retryFailedUserMessage(id: failedMessage.id)

        try await waitUntil("custom plan follow-up retry sent") {
            await fixture.agentsManager.sentMessages() == ["Please revise the plan first."]
        }
        XCTAssertFalse(fixture.viewModel.state.retryableFailedMessageIDs.contains(failedMessage.id))
    }

    func testCustomDenyFollowUpDoesNotUseLiveStagedContextWhenInitialSetupRuns() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: false,
            initialAgentIsRunning: false
        )
        let conversation = try fixture.dbConversation()
        let approval = exitPlanModeApproval(toolUseId: "exit-plan-1")
        fixture.context.insert(exitPlanModeApprovalRecord(conversation: conversation, approval: approval))
        try fixture.context.save()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
        fixture.viewModel.state.stagedContext = "Live staged context"

        try await fixture.viewModel.denyExitPlanMode(
            toolUseId: approval.toolUseId,
            followUp: "Please revise the plan first."
        )

        try await waitUntil("custom plan follow-up started without live staged context during setup") {
            let spawnCalls = await fixture.agentsManager.spawnCalls()
            return spawnCalls.first?.config.initialPrompt == "Please revise the plan first."
        }

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Please revise the plan first."])
        XCTAssertTrue(try fixture.dbThread().hasCompletedInitialSetup)
        XCTAssertEqual(fixture.viewModel.state.stagedContext, "Live staged context")
    }

    func testCustomDenyFollowUpClearsWhenApprovalFails() async throws {
        let fixture = try ConversationViewModelTestFixture(
            approvalError: .approvalFailed,
            initialAgentIsRunning: false
        )
        let approval = exitPlanModeApproval(toolUseId: "exit-plan-1")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        do {
            try await fixture.viewModel.denyExitPlanMode(
                toolUseId: approval.toolUseId,
                followUp: "Revise it."
            )
            XCTFail("Expected denial to fail")
        } catch {}

        XCTAssertNil(fixture.viewModel.state.pendingExitPlanModeFollowUp)
        XCTAssertNil(fixture.viewModel.state.pendingExitPlanModeFollowUpQuietTask)
        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.status, .pending)
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

@MainActor
private func conversationRecords(
    for fixture: ConversationViewModelTestFixture
) throws -> [ConversationEventRecord] {
    try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
        $0.conversationId == fixture.conversation.id
    }.sorted { lhs, rhs in
        if lhs.timestamp == rhs.timestamp {
            return lhs.id < rhs.id
        }
        return lhs.timestamp < rhs.timestamp
    }
}

private func exitPlanModeApprovalRecord(
    conversation: Conversation,
    approval: ToolApprovalRequest
) -> ConversationEventRecord {
    ConversationEventRecord(
        conversationId: conversation.id,
        type: "tool_approval",
        content: approval.sessionId,
        toolId: approval.toolUseId,
        toolName: approval.toolName,
        toolInput: approval.toolInput,
        conversation: conversation
    )
}

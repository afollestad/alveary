import AgentCLIKit
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testAutomaticSessionHandoffDoesNotTriggerBeforeTurnCompletion() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.turnState.beginTurn()
        fixture.viewModel.state.messageQueue.enqueue("Queued follow-up", stagedContext: nil)

        fixture.viewModel.handleEvent(.tokens(
            input: 190,
            output: 5,
            cacheRead: 0,
            isError: false,
            stopReason: nil,
            durationMs: 10,
            costUsd: 0.01,
            contextWindowSize: 200,
            permissionDenials: []
        ))
        await Task.yield()

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(fixture.viewModel.state.isAutomaticSessionHandoffPending)
        XCTAssertFalse(fixture.viewModel.state.hasActiveSessionHandoff)
        XCTAssertTrue(fixture.viewModel.turnState.isActive)
        XCTAssertEqual(fixture.viewModel.state.messageQueue.pending.map(\.text), ["Queued follow-up"])
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testAutomaticSessionHandoffTriggersAfterCompletedThresholdToken() async throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.handleEvent(.tokens(
            input: 190,
            output: 5,
            cacheRead: 0,
            isError: false,
            stopReason: nil,
            durationMs: 10,
            costUsd: 0.01,
            contextWindowSize: 200,
            permissionDenials: []
        ))
        await Task.yield()
        XCTAssertTrue(fixture.viewModel.state.isAutomaticSessionHandoffPending)
        XCTAssertFalse(fixture.viewModel.state.hasActiveSessionHandoff)

        fixture.viewModel.handleEvent(.tokens(
            input: 0,
            output: 0,
            cacheRead: 0,
            isError: false,
            stopReason: "end_turn",
            durationMs: 10,
            costUsd: 0.01,
            contextWindowSize: nil,
            permissionDenials: []
        ))

        try await waitUntil("automatic handoff steering prompt shown") {
            fixture.viewModel.state.isAwaitingHandoffSteering
        }
    }

    func testAutomaticSessionHandoffPendingClearsOnExplicitStop() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.turnState.beginTurn()

        fixture.viewModel.handleEvent(.tokens(
            input: 190,
            output: 5,
            cacheRead: 0,
            isError: false,
            stopReason: nil,
            durationMs: 10,
            costUsd: 0.01,
            contextWindowSize: 200,
            permissionDenials: []
        ))
        XCTAssertTrue(fixture.viewModel.state.isAutomaticSessionHandoffPending)

        fixture.viewModel.handleEvent(.stop(message: ConversationInterruption.displayMessage))

        XCTAssertFalse(fixture.viewModel.state.isAutomaticSessionHandoffPending)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertTrue(fixture.viewModel.state.lastTurnInterrupted)
    }

    func testHiddenSessionHandoffIgnoresInterimUsageBeforeOutput() async throws {
        let fixture = try ConversationViewModelTestFixture()

        await fixture.viewModel.startSessionHandoff(trigger: .manual)
        try await waitUntil("handoff prompt sent") {
            await fixture.agentsManager.sentMessages() == [AppSettings.defaultSessionHandoffPrompt]
        }

        fixture.viewModel.handleEvent(.tokens(
            input: 10,
            output: 0,
            cacheRead: 0,
            isError: false,
            stopReason: "usage_update",
            durationMs: 10,
            costUsd: 0.01,
            contextWindowSize: 200,
            permissionDenials: []
        ))

        let freshSessionCallsBeforeOutput = await fixture.agentsManager.freshSessionCalls()
        XCTAssertTrue(freshSessionCallsBeforeOutput.isEmpty)
        XCTAssertTrue(fixture.viewModel.state.isHandingOffSession)
        XCTAssertNil(fixture.viewModel.lastTurnError)
        XCTAssertNil(fixture.viewModel.state.failedSessionHandoffMessage)

        fixture.viewModel.handleEvent(.messageChunk(text: "Recovered ", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.messageChunk(text: "context.", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.tokens(
            input: 10,
            output: 5,
            cacheRead: 0,
            isError: false,
            stopReason: "end_turn",
            durationMs: 10,
            costUsd: 0.01,
            contextWindowSize: 200,
            permissionDenials: []
        ))

        try await waitUntil("session handoff recovered") {
            let freshSessionCount = await fixture.agentsManager.freshSessionCalls().count
            return !fixture.viewModel.state.isHandingOffSession && freshSessionCount == 1
        }

        XCTAssertNil(fixture.viewModel.lastTurnError)
        XCTAssertNil(fixture.viewModel.state.failedSessionHandoffMessage)
        XCTAssertEqual(fixture.viewModel.state.pendingHandoffOutput, "Recovered context.")
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Recovered context.")
    }

    func testSessionHandoffFreshSessionFailureResubscribesWhenRuntimeStillRunning() async throws {
        let fixture = try ConversationViewModelTestFixture(
            reconfigureError: .reconfigureFailed,
            initialAgentIsRunning: true
        )
        await fixture.agentsManager.enableSubscription()
        fixture.viewModel.activateViewLifecycle()
        try await waitUntil("expected initial subscription") {
            await fixture.agentsManager.subscribeCalls() == 1
        }

        await fixture.viewModel.startSessionHandoff(trigger: .manual)
        try await waitUntil("handoff prompt sent") {
            await fixture.agentsManager.sentMessages() == [AppSettings.defaultSessionHandoffPrompt]
        }
        fixture.viewModel.handleEvent(.messageChunk(text: "Collected context.", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.tokens(
            input: 10,
            output: 5,
            cacheRead: 0,
            isError: false,
            stopReason: "end_turn",
            durationMs: 10,
            costUsd: 0.01,
            contextWindowSize: 200,
            permissionDenials: []
        ))

        try await waitUntil("expected failed fresh session to resubscribe") {
            await fixture.agentsManager.subscribeCalls() == 2
        }
        XCTAssertFalse(fixture.viewModel.state.isHandingOffSession)
        XCTAssertTrue(fixture.viewModel.state.failedSessionHandoffMessage?.hasPrefix("Session handoff failed:") == true)
        XCTAssertTrue(fixture.viewModel.state.failedSessionHandoffMessage?.contains("MockAgentsManager.MockError") == true)
    }

    func testHiddenSessionHandoffStripsOuterMarkdownFenceBeforeCustomization() async throws {
        let fixture = try ConversationViewModelTestFixture()

        await fixture.viewModel.startSessionHandoff(trigger: .manual)
        try await waitUntil("handoff prompt sent") {
            await fixture.agentsManager.sentMessages() == [AppSettings.defaultSessionHandoffPrompt]
        }

        fixture.viewModel.handleEvent(.message(
            role: "assistant",
            content: "```markdown\nPrimary goal:\n- Continue the work.\n```",
            parentToolUseId: nil
        ))
        fixture.viewModel.handleEvent(.tokens(
            input: 10,
            output: 5,
            cacheRead: 0,
            isError: false,
            stopReason: "end_turn",
            durationMs: 10,
            costUsd: 0.01,
            contextWindowSize: 200,
            permissionDenials: []
        ))

        try await waitUntil("session handoff finished hidden response") {
            let freshSessionCount = await fixture.agentsManager.freshSessionCalls().count
            return !fixture.viewModel.state.isHandingOffSession && freshSessionCount == 1
        }

        XCTAssertEqual(fixture.viewModel.state.pendingHandoffOutput, "Primary goal:\n- Continue the work.")
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Primary goal:\n- Continue the work.")
    }

    func testHiddenSessionHandoffFallsBackToLocalHistoryWhenCodexResumeHasNoRollout() async throws {
        let fixture = try ConversationViewModelTestFixture(
            initialAgentIsRunning: false,
            providerId: "codex"
        )
        try await seedCodexNoRolloutHandoffFixture(
            fixture,
            userMessage: "Please continue the index.html review.",
            assistantMessage: "The page summary is partially written."
        )

        await fixture.viewModel.startSessionHandoff(trigger: .manual)

        try await waitUntil("local fallback handoff staged") {
            let freshSessionCount = await fixture.agentsManager.freshSessionCalls().count
            return !fixture.viewModel.state.isHandingOffSession && freshSessionCount == 1
        }

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        let hiddenPromptSends = await fixture.agentsManager.sentMessages()
        let output = try XCTUnwrap(fixture.viewModel.state.pendingHandoffOutput)
        XCTAssertEqual(spawnCalls.count, 1)
        XCTAssertTrue(hiddenPromptSends.isEmpty)
        XCTAssertNil(fixture.viewModel.lastTurnError)
        XCTAssertNil(fixture.viewModel.state.failedSessionHandoffMessage)
        XCTAssertTrue(output.contains("The hidden session handoff agent could not resume the previous provider session."))
        XCTAssertTrue(output.contains("Restoring context from local history."))
        XCTAssertTrue(output.contains("User: Please continue the index.html review."))
        XCTAssertTrue(output.contains("Assistant: The page summary is partially written."))
        XCTAssertFalse(output.contains(ConversationSessionHandoff.startedDisplayMessage))
        XCTAssertFalse(output.contains(ConversationSessionHandoff.completedDisplayMessage))
        XCTAssertEqual(fixture.viewModel.state.inputDraft, output)

        let records = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>())
        let handoffNotes = records.filter { ConversationSessionHandoff.isDisplayMessage($0.content) }
        XCTAssertEqual(handoffNotes.count, 1)
        XCTAssertEqual(handoffNotes.first?.content, ConversationSessionHandoff.completedDisplayMessage)
    }

    func testPlanModeLocalHistoryHandoffFallbackKeepsPlanModeContext() async throws {
        let fixture = try ConversationViewModelTestFixture(
            initialAgentIsRunning: false,
            providerId: "codex"
        )
        fixture.viewModel.state.runtimePlanModeEnabled = true
        try await seedCodexNoRolloutHandoffFixture(
            fixture,
            userMessage: "Review the current implementation plan."
        )

        await fixture.viewModel.startSessionHandoff(trigger: .manual)

        try await waitUntil("plan-mode local fallback staged") {
            let freshSessionCount = await fixture.agentsManager.freshSessionCalls().count
            return !fixture.viewModel.state.isHandingOffSession && freshSessionCount == 1
        }
        let output = try XCTUnwrap(fixture.viewModel.state.pendingHandoffOutput)
        XCTAssertTrue(output.hasPrefix(planModeHandoffPrefix))
        let instructionRange = try XCTUnwrap(output.range(of: planModeHandoffInstruction))
        let fallbackRange = try XCTUnwrap(output.range(of: "The hidden session handoff agent could not resume"))
        XCTAssertLessThan(instructionRange.lowerBound, fallbackRange.lowerBound)
    }
}

@MainActor
private func seedCodexNoRolloutHandoffFixture(
    _ fixture: ConversationViewModelTestFixture,
    userMessage: String,
    assistantMessage: String? = nil
) async throws {
    let conversation = try fixture.dbConversation()
    fixture.context.insert(ConversationEventRecord(
        conversationId: conversation.id,
        type: "message",
        role: "user",
        content: userMessage,
        timestamp: Date(timeIntervalSince1970: 1),
        conversation: conversation
    ))
    if let assistantMessage {
        fixture.context.insert(ConversationEventRecord(
            conversationId: conversation.id,
            type: "message",
            role: "assistant",
            content: assistantMessage,
            timestamp: Date(timeIntervalSince1970: 2),
            conversation: conversation
        ))
    }
    try fixture.context.save()
    await fixture.agentsManager.enqueueSpawnError(
        CodexAppServerError.jsonRPCError(
            method: "thread/resume",
            code: -32600,
            message: "no rollout found for thread id 019ee845-0b26-7061-af79-9bd2327f8401"
        )
    )
}

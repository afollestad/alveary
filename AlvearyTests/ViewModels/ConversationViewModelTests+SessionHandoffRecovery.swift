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
}

import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testSteerDuringSessionHandoffDoesNotInsertUserMessage() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.setStatus(.busy, for: fixture.conversation.id)
        fixture.viewModel.state.isHandingOffSession = true

        do {
            try await fixture.viewModel.steer("Do not steer during handoff")
            XCTFail("Expected steering during session handoff to fail")
        } catch {
            XCTAssertEqual(error as? AgentError, AgentError.spawnFailed("Session handoff is in progress"))
        }

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertTrue(try fixture.userMessages().isEmpty)
    }

    func testSteerQueuedMessageDuringSessionHandoffLeavesMessageQueued() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.messageQueue.enqueue("Queued steer", stagedContext: "Queued context")
        await fixture.agentsManager.setStatus(.busy, for: fixture.conversation.id)
        fixture.viewModel.state.isHandingOffSession = true

        let queuedID = try XCTUnwrap(fixture.viewModel.messageQueue.peekNext()?.id)
        do {
            try await fixture.viewModel.steerQueuedMessage(id: queuedID)
            XCTFail("Expected queued steering during session handoff to fail")
        } catch {
            XCTAssertEqual(error as? AgentError, AgentError.spawnFailed("Session handoff is in progress"))
        }

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertEqual(fixture.viewModel.messageQueue.pending.map(\.text), ["Queued steer"])
        XCTAssertTrue(try fixture.userMessages().isEmpty)
        XCTAssertNil(fixture.viewModel.state.inFlightQueuedMessageID)
    }

    func testSteerNextQueuedMessageDuringSessionHandoffDoesNotRemoveHeadMessage() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.messageQueue.enqueue("Queued during handoff", stagedContext: nil)
        await fixture.agentsManager.setStatus(.busy, for: fixture.conversation.id)
        fixture.viewModel.state.pendingHandoffOutput = "Seed the fresh session."

        do {
            try await fixture.viewModel.steerNextQueuedMessage()
            XCTFail("Expected next queued message steering during session handoff to fail")
        } catch {
            XCTAssertEqual(error as? AgentError, AgentError.spawnFailed("Session handoff is in progress"))
        }

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertEqual(fixture.viewModel.messageQueue.pending.map(\.text), ["Queued during handoff"])
        XCTAssertTrue(try fixture.userMessages().isEmpty)
    }

    func testQueuedSteeringStaysDisabledUntilHandoffSeedTurnCompletes() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.messageQueue.enqueue("Queued after handoff", stagedContext: nil)
        try await completeHiddenSessionHandoffForSteeringBlock(fixture: fixture, output: "Seed the fresh session.")

        fixture.viewModel.state.handoffCountdownRemaining = 0
        await fixture.viewModel.autoSendSessionHandoffOutputIfUnedited()

        try await waitUntil("handoff output sent") {
            await fixture.agentsManager.sentMessages() == [
                AppSettings.defaultSessionHandoffPrompt,
                "Seed the fresh session."
            ]
        }
        XCTAssertFalse(fixture.viewModel.state.hasActiveSessionHandoff)
        XCTAssertTrue(fixture.viewModel.state.isSessionHandoffSeedTurnActive)
        XCTAssertTrue(fixture.viewModel.turnState.isActive)

        let queuedID = try XCTUnwrap(fixture.viewModel.state.messageQueue.peekNext()?.id)
        do {
            try await fixture.viewModel.steerQueuedMessage(id: queuedID)
            XCTFail("Expected queued steering to stay blocked during the handoff seed turn")
        } catch {
            XCTAssertEqual(error as? AgentError, AgentError.spawnFailed("Session handoff is in progress"))
        }
        XCTAssertEqual(fixture.viewModel.state.messageQueue.pending.map(\.text), ["Queued after handoff"])
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Seed the fresh session."])

        fixture.viewModel.handleEvent(.tokens(
            input: 1,
            output: 1,
            cacheRead: 0,
            isError: false,
            stopReason: "end_turn",
            durationMs: 10,
            costUsd: 0.01,
            contextWindowSize: 200,
            permissionDenials: []
        ))
        XCTAssertFalse(fixture.viewModel.state.isSessionHandoffSeedTurnActive)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)

        await fixture.agentsManager.setStatus(.busy, for: fixture.conversation.id)
        try await fixture.viewModel.steerQueuedMessage(id: queuedID)

        try await waitUntil("queued message steered after seed turn completion") {
            await fixture.agentsManager.sentMessages() == [
                AppSettings.defaultSessionHandoffPrompt,
                "Seed the fresh session.",
                "Queued after handoff"
            ]
        }
        XCTAssertTrue(fixture.viewModel.state.messageQueue.pending.isEmpty)
        XCTAssertEqual(Set(try fixture.userMessages().map(\.content)), Set(["Seed the fresh session.", "Queued after handoff"]))
    }

    func testHandoffSeedTurnFailureClearsSteeringBlock() async throws {
        let fixture = try ConversationViewModelTestFixture()
        try await completeHiddenSessionHandoffForSteeringBlock(fixture: fixture, output: "Seed the fresh session.")

        fixture.viewModel.state.handoffCountdownRemaining = 0
        await fixture.viewModel.autoSendSessionHandoffOutputIfUnedited()

        try await waitUntil("handoff output sent") {
            await fixture.agentsManager.sentMessages() == [
                AppSettings.defaultSessionHandoffPrompt,
                "Seed the fresh session."
            ]
        }
        XCTAssertTrue(fixture.viewModel.state.isSessionHandoffSeedTurnActive)

        fixture.viewModel.handleEvent(.error(message: "seed failed"))

        XCTAssertFalse(fixture.viewModel.state.isSessionHandoffSeedTurnActive)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)

        await fixture.agentsManager.setStatus(.busy, for: fixture.conversation.id)
        XCTAssertTrue(fixture.viewModel.canSteerCurrentTurn)
    }
}

@MainActor
private func completeHiddenSessionHandoffForSteeringBlock(
    fixture: ConversationViewModelTestFixture,
    output: String
) async throws {
    await fixture.viewModel.startSessionHandoff(trigger: .manual)
    try await waitUntil("handoff prompt sent") {
        await fixture.agentsManager.sentMessages() == [AppSettings.defaultSessionHandoffPrompt]
    }

    fixture.viewModel.handleEvent(.messageChunk(text: "partial", parentToolUseId: nil))
    fixture.viewModel.handleEvent(.message(role: "assistant", content: output, parentToolUseId: nil))
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
}

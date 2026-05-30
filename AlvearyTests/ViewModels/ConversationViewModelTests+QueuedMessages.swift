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

    func testQueueOrSendWhileRuntimeIdleSendsImmediately() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.setStatus(.idle, for: fixture.conversation.id)

        try await fixture.viewModel.queueOrSend("Send now")

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertNil(fixture.viewModel.messageQueue.peekNext())
        XCTAssertEqual(sentMessages, ["Send now"])
        XCTAssertTrue(fixture.viewModel.turnState.isActive)
    }

    func testQueuedMessageFailureMovesRetryToTranscriptMessage() async throws {
        let fixture = try ConversationViewModelTestFixture()
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
}

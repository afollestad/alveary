import XCTest

@testable import Alveary

@MainActor
extension ChatComposerDraftTests {
    func testSendDraftWithPausedQueueShowsConfirmationAndKeepsDraftQueued() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let appState = AppState()
        fixture.viewModel.state.messageQueue.enqueue("Queued one", stagedContext: nil)
        fixture.viewModel.state.messageQueue.enqueue("Queued two", stagedContext: nil)
        fixture.viewModel.state.queuedMessagesPauseReason = .interrupted
        fixture.viewModel.replaceInputDraft("Send this now", source: .blockInputMarkdown)
        let chatView = makeChatView(fixture: fixture, appState: appState)

        chatView.sendDraft()

        let confirmation = try XCTUnwrap(fixture.viewModel.state.pausedQueueSendConfirmation)
        XCTAssertTrue(try XCTUnwrap(chatView.pausedQueueSendModal).id.hasPrefix("paused-queue-send-\(confirmation.id)"))
        XCTAssertNil(chatView.composerInteractionOverlayConfiguration)
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Send this now")
        XCTAssertEqual(fixture.viewModel.messageQueue.pending.map(\.text), ["Queued one", "Queued two"])
        XCTAssertNil(appState.pendingComposerFocusToken)
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testPausedQueueSendConfirmationCloseKeepsDraftAndQueue() throws {
        let fixture = try ConversationViewModelTestFixture()
        let appState = AppState()
        fixture.viewModel.state.messageQueue.enqueue("Queued one", stagedContext: nil)
        fixture.viewModel.state.queuedMessagesPauseReason = .interrupted
        fixture.viewModel.replaceInputDraft("Send this now", source: .blockInputMarkdown)
        let chatView = makeChatView(fixture: fixture, appState: appState)

        chatView.sendDraft()
        XCTAssertNotNil(chatView.pausedQueueSendModal)
        chatView.dismissPausedQueueSendConfirmation()

        XCTAssertNil(fixture.viewModel.state.pausedQueueSendConfirmation)
        XCTAssertEqual(fixture.viewModel.state.queuedMessagesPauseReason, .interrupted)
        XCTAssertEqual(fixture.viewModel.messageQueue.pending.map(\.text), ["Queued one"])
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Send this now")
        XCTAssertNotNil(appState.pendingComposerFocusToken)
    }

    func testPausedQueueSendConfirmationClearQueueSendsDraft() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let appState = AppState()
        fixture.viewModel.state.messageQueue.enqueue("Queued one", stagedContext: nil)
        fixture.viewModel.state.messageQueue.enqueue("Queued two", stagedContext: nil)
        fixture.viewModel.state.queuedMessagesPauseReason = .interrupted
        fixture.viewModel.state.lastTurnInterrupted = true
        fixture.viewModel.replaceInputDraft("Send this now", source: .blockInputMarkdown)
        let chatView = makeChatView(fixture: fixture, appState: appState)

        chatView.sendDraft()
        XCTAssertNotNil(chatView.pausedQueueSendModal)
        chatView.clearPausedQueueFromSendConfirmation()

        XCTAssertNil(fixture.viewModel.state.pausedQueueSendConfirmation)
        XCTAssertNil(fixture.viewModel.state.queuedMessagesPauseReason)
        XCTAssertTrue(fixture.viewModel.messageQueue.pending.isEmpty)
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertNotNil(appState.pendingComposerFocusToken)
        try await waitUntil("expected clear queue action to send current draft") {
            await fixture.agentsManager.sentMessages() == ["Send this now"]
        }
        XCTAssertFalse(fixture.viewModel.state.lastTurnInterrupted)
    }

    func testPausedQueueSendConfirmationSendMessageResumesQueueAndSendsDraft() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let appState = AppState()
        fixture.viewModel.state.messageQueue.enqueue("Queued one", stagedContext: nil)
        fixture.viewModel.state.messageQueue.enqueue("Queued two", stagedContext: nil)
        fixture.viewModel.state.queuedMessagesPauseReason = .interrupted
        fixture.viewModel.state.lastTurnInterrupted = true
        fixture.viewModel.replaceInputDraft("Send this now", source: .blockInputMarkdown)
        let chatView = makeChatView(fixture: fixture, appState: appState)

        chatView.sendDraft()
        XCTAssertNotNil(chatView.pausedQueueSendModal)
        chatView.sendPausedQueueConfirmedDraft()

        XCTAssertNil(fixture.viewModel.state.pausedQueueSendConfirmation)
        XCTAssertEqual(fixture.viewModel.messageQueue.pending.map(\.text), ["Queued one", "Queued two"])
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertNotNil(appState.pendingComposerFocusToken)
        try await waitUntil("expected confirmed paused queue send to send current draft") {
            await fixture.agentsManager.sentMessages() == ["Send this now"]
        }
        XCTAssertNil(fixture.viewModel.state.queuedMessagesPauseReason)
        XCTAssertEqual(fixture.viewModel.messageQueue.pending.map(\.text), ["Queued one", "Queued two"])
        XCTAssertFalse(fixture.viewModel.state.lastTurnInterrupted)
    }

    func testPausedQueueSendConfirmationSendMessageDuringActiveTurnRestoresDraftAndKeepsQueuePaused() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let appState = AppState()
        fixture.viewModel.state.messageQueue.enqueue("Queued one", stagedContext: nil)
        fixture.viewModel.state.queuedMessagesPauseReason = .interrupted
        fixture.viewModel.replaceInputDraft("Send this now", source: .blockInputMarkdown)
        let chatView = makeChatView(fixture: fixture, appState: appState)

        chatView.sendDraft()
        XCTAssertNotNil(chatView.pausedQueueSendModal)

        fixture.viewModel.state.turnState.beginTurn()
        chatView.sendPausedQueueConfirmedDraft()

        XCTAssertNil(fixture.viewModel.state.pausedQueueSendConfirmation)
        XCTAssertEqual(fixture.viewModel.messageQueue.pending.map(\.text), ["Queued one"])
        XCTAssertNotNil(appState.pendingComposerFocusToken)
        try await waitUntil("expected active-turn paused queue send to restore draft") {
            fixture.viewModel.state.inputDraft == "Send this now" &&
                fixture.viewModel.lastTurnError == "Wait for the current turn/send to finish before sending another message"
        }
        XCTAssertEqual(fixture.viewModel.state.queuedMessagesPauseReason, .interrupted)
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }
}

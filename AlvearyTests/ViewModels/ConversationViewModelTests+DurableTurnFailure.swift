import Foundation
import XCTest

@testable import Alveary

/// `Conversation.lastTurnFailedAt` is the durable half of `ThreadStatus.error`. Every failure path
/// reaches it through the one classifier, `ConversationState.recordControllerTerminalBoundary()`,
/// so these cover the shapes that must set it, the ones that must clear it, and the two that must
/// leave it alone.
@MainActor
extension ConversationViewModelTests {
    func testProviderErrorEventMarksTheConversationDurablyFailed() throws {
        let fixture = try ConversationViewModelTestFixture()
        beginVisibleTurn(fixture)

        fixture.viewModel.handleEvent(.error(message: "API Error: Connection dropped (ECONNRESET)"))

        XCTAssertNotNil(fixture.conversation.lastTurnFailedAt)
    }

    func testRuntimeActivityFailedTurnMarksDurableFailure() throws {
        let fixture = try ConversationViewModelTestFixture()
        beginVisibleTurn(fixture)

        fixture.viewModel.handleEvent(
            .runtimeActivity(state: .idle, turnId: nil, outcome: .failed(message: "Agent turn failed"))
        )

        XCTAssertNotNil(fixture.conversation.lastTurnFailedAt)
    }

    func testTerminalTokenErrorMarksDurableFailure() throws {
        let fixture = try ConversationViewModelTestFixture()
        beginVisibleTurn(fixture)

        fixture.viewModel.handleEvent(terminalTokens(isError: true, stopReason: "api_error"))

        XCTAssertNotNil(fixture.conversation.lastTurnFailedAt)
    }

    /// A stream that dies mid-turn emits no terminal event of its own, so the subscription's own
    /// "connection ended before the turn completed" boundary has to carry the failure.
    func testSubscriptionDeathDuringActiveTurnMarksDurableFailure() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.enableSubscription()
        fixture.viewModel.subscribe()
        try await waitUntil("subscription becomes active", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            await fixture.agentsManager.hasActiveSubscription()
        }
        beginVisibleTurn(fixture)

        await fixture.agentsManager.finishSubscription()

        try await waitUntil("stream death recorded a durable failure") {
            fixture.conversation.lastTurnFailedAt != nil
        }
    }

    func testSuccessfulTurnClearsDurableFailure() throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.conversation.lastTurnFailedAt = Date()
        beginVisibleTurn(fixture)

        fixture.viewModel.handleEvent(terminalTokens(isError: false, stopReason: "end_turn"))

        XCTAssertNil(fixture.conversation.lastTurnFailedAt)
    }

    /// Cancelling is not failing — `Alveary/Views/AGENTS.md` maps cancelled orange, error red.
    func testUserInterruptionClearsDurableFailure() throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.conversation.lastTurnFailedAt = Date()
        beginVisibleTurn(fixture)
        fixture.viewModel.state.lastTurnInterrupted = true

        fixture.viewModel.handleEvent(.stop(message: ConversationInterruption.displayMessage))

        XCTAssertNil(fixture.conversation.lastTurnFailedAt)
    }

    /// The invariant `ThreadStatus.folded` leans on: the flag is gone before the new turn can
    /// report anything, so a surviving flag always means no turn started since the failure.
    func testNewVisibleTurnClearsDurableFailureBeforeTheProviderReplies() throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.conversation.lastTurnFailedAt = Date()

        fixture.viewModel.markVisibleTurnStarted()

        XCTAssertNil(fixture.conversation.lastTurnFailedAt)
    }

    /// A failed commit-message generation must not paint the thread red.
    func testHiddenTurnFailureLeavesNoDurableFailure() throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.beginHiddenActivityTurn()

        fixture.viewModel.handleEvent(.error(message: "Agent process failed"))

        XCTAssertNil(fixture.conversation.lastTurnFailedAt)
    }

    /// Locks the ordering: the clear runs before the dispatch, not with `markVisibleTurnStarted()`
    /// after it. A send that never reaches the provider proves which side of the dispatch it is on,
    /// and the dispatch is what puts the runtime in `.busy` the fold would otherwise suppress.
    func testAttemptingASendClearsDurableFailureBeforeDispatching() async throws {
        let fixture = try ConversationViewModelTestFixture(sendError: .sendFailed)
        fixture.conversation.lastTurnFailedAt = Date()

        do {
            try await fixture.viewModel.queueOrSend("Retry")
        } catch {
            // Expected: the dispatch fails, but the attempt still supersedes the old failure.
        }

        XCTAssertNil(fixture.conversation.lastTurnFailedAt)
    }

    /// `restoreStateAfterFailedInitialSetup` swaps the state, so the writer has to be reinstalled
    /// or outcomes stop persisting after any rollback.
    func testReplacedConversationStateStillPersistsTerminalOutcomes() throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.replaceState(with: ConversationState())
        beginVisibleTurn(fixture)

        fixture.viewModel.handleEvent(.error(message: "API Error: Connection dropped (ECONNRESET)"))

        XCTAssertNotNil(fixture.conversation.lastTurnFailedAt)
    }

    private func beginVisibleTurn(_ fixture: ConversationViewModelTestFixture) {
        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()
    }

    private func terminalTokens(isError: Bool, stopReason: String) -> ConversationEvent {
        .tokens(
            input: 1,
            output: 1,
            cacheRead: 0,
            isError: isError,
            stopReason: stopReason,
            durationMs: 0,
            costUsd: nil,
            permissionDenials: [],
            isTerminal: true
        )
    }
}

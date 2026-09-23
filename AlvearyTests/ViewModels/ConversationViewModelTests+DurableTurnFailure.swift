import Foundation
import XCTest

@testable import Alveary

/// `Conversation.lastTurnFailedAt` is the durable half of `ThreadStatus.error`. Every turn failure
/// reaches it through the one classifier, `ConversationState.recordControllerTerminalBoundary()`,
/// so these cover the shapes that must set it, the ones that must clear it, and the two that must
/// leave it alone — plus the unattended first send that fails before any turn begins.
@MainActor
extension ConversationViewModelTests {
    func testHarnessErrorEventMarksTheConversationDurablyFailed() throws {
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
        beginVisibleTurn(fixture)
        let previousFailure = Date(timeIntervalSince1970: 100)
        fixture.conversation.lastTurnFailedAt = previousFailure
        XCTAssertEqual(fixture.conversation.lastTurnFailedAt, previousFailure)

        fixture.viewModel.handleEvent(terminalTokens(isError: false, stopReason: "end_turn"))

        XCTAssertEqual(fixture.viewModel.state.lastControllerTerminalBoundary?.wasVisible, true)
        XCTAssertEqual(fixture.viewModel.state.lastControllerTerminalBoundary?.result, .succeeded)
        XCTAssertNil(fixture.conversation.lastTurnFailedAt)
    }

    /// Cancelling is not failing — `Alveary/Views/AGENTS.md` maps cancelled orange, error red.
    func testUserInterruptionClearsDurableFailure() throws {
        let fixture = try ConversationViewModelTestFixture()
        beginVisibleTurn(fixture)
        let previousFailure = Date(timeIntervalSince1970: 100)
        fixture.conversation.lastTurnFailedAt = previousFailure
        XCTAssertEqual(fixture.conversation.lastTurnFailedAt, previousFailure)
        fixture.viewModel.state.lastTurnInterrupted = true

        fixture.viewModel.handleEvent(.stop(message: ConversationInterruption.displayMessage))

        XCTAssertEqual(fixture.viewModel.state.lastControllerTerminalBoundary?.wasVisible, true)
        XCTAssertEqual(fixture.viewModel.state.lastControllerTerminalBoundary?.result, .interrupted)
        XCTAssertNil(fixture.conversation.lastTurnFailedAt)
    }

    /// The invariant `ThreadStatus.folded` leans on: the flag is gone before the new turn can
    /// report anything, so a surviving flag always means no turn started since the failure.
    func testNewVisibleTurnClearsDurableFailureBeforeTheHarnessReplies() throws {
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
    /// after it. A send that never reaches the harness proves which side of the dispatch it is on,
    /// and the dispatch is what puts the runtime in `.busy` the fold would otherwise suppress.
    func testAttemptingASendClearsDurableFailureBeforeDispatching() async throws {
        let fixture = try ConversationViewModelTestFixture(sendError: .sendFailed)
        fixture.conversation.lastTurnFailedAt = Date()

        do {
            try await fixture.viewModel.queueOrSend("Retry")
            XCTFail("Expected dispatch to fail")
        } catch MockAgentsManager.MockError.sendFailed {
            // The attempt supersedes the old failure even though dispatch failed.
        }

        XCTAssertNil(fixture.conversation.lastTurnFailedAt)
    }

    /// A background first send that fails to spawn leaves a "Not sent" row nobody is looking at, so
    /// its caller marks the failure the view-model rollback deliberately leaves unset.
    func testUnattendedStartFailureMarksTheConversationFailed() async throws {
        let fixture = try ConversationViewModelTestFixture(hasCompletedInitialSetup: false, harnessId: "codex")
        await fixture.agentsManager.enqueueSpawnError(MockAgentsManager.MockError.sendFailed)
        do {
            try await fixture.viewModel.setupAndStart("Review pull request: https://example.com/pull/1")
            XCTFail("Expected initial setup to throw")
        } catch MockAgentsManager.MockError.sendFailed {}
        XCTAssertNil(fixture.conversation.lastTurnFailedAt)

        fixture.viewModel.recordUnattendedStartFailure()

        XCTAssertNotNil(fixture.conversation.lastTurnFailedAt)
    }

    /// Once setup has run, a turn owns the flag.
    func testUnattendedStartFailureLeavesACompletedSetupAlone() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.recordUnattendedStartFailure()

        XCTAssertNil(fixture.conversation.lastTurnFailedAt)
    }

    /// A thread whose setup never completed sends through initial setup, which posts `.busy` at
    /// spawn; `markVisibleTurnStarted()` only runs after it, so the clear must precede the spawn.
    func testInitialSetupClearsDurableFailureBeforeSpawning() async throws {
        let fixture = try ConversationViewModelTestFixture(hasCompletedInitialSetup: false, harnessId: "codex")
        fixture.conversation.lastTurnFailedAt = Date()
        let probe = DurableFailureSpawnProbe()
        let viewModel = fixture.viewModel
        await fixture.agentsManager.setSpawnPrologue {
            probe.failedAtSpawn = viewModel.dbConversation()?.lastTurnFailedAt
            probe.didSpawn = true
        }

        try await fixture.viewModel.setupAndStart("Review pull request: https://example.com/pull/1")

        XCTAssertTrue(probe.didSpawn)
        XCTAssertNil(probe.failedAtSpawn)
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

/// What the durable failure read when the spawn began. The spawn prologue is `@Sendable`, so it
/// records into this rather than capturing the non-Sendable `Conversation`.
@MainActor
private final class DurableFailureSpawnProbe {
    var didSpawn = false
    var failedAtSpawn: Date?
}

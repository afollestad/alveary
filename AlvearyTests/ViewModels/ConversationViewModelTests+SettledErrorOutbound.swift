import Foundation
import XCTest

@testable import Alveary

/// A failed turn leaves the runtime settled at `.error`, which is a finished turn like `.stopped`.
/// These lock that outbound treats it that way instead of parking the user's next message behind a
/// turn that will never report anything again.
@MainActor
extension ConversationViewModelTests {
    func testOrdinaryMessageSendsWhenRuntimeSettledError() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.setStatus(.error, for: fixture.conversation.id)

        try await fixture.viewModel.queueOrSend("Retry")

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertNil(fixture.viewModel.messageQueue.peekNext())
        XCTAssertEqual(sentMessages, ["Retry"])
    }

    func testQueuedMessageDrainsAfterTurnFailureSettlesError() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.activateViewLifecycle()
        await fixture.agentsManager.setStatus(.busy, for: fixture.conversation.id)
        fixture.viewModel.turnState.beginTurn()

        try await fixture.viewModel.queueOrSend("Retry")
        XCTAssertEqual(fixture.viewModel.messageQueue.peekNext()?.text, "Retry")

        // The turn dies mid-stream; the runtime settles at `.error` and `ConversationView`'s
        // status observer re-arms the drain, exactly as it does in the app.
        await fixture.agentsManager.setStatus(.error, for: fixture.conversation.id)
        await fixture.agentsManager.enqueueRefreshStatus(.error)
        fixture.viewModel.handleEvent(.error(message: "API Error: Connection dropped (ECONNRESET)"))
        fixture.viewModel.scheduleQueueDrainIfNeeded()

        try await waitUntil("queued message sent after the failed turn settled") {
            await fixture.agentsManager.sentMessages() == ["Retry"] &&
                fixture.viewModel.messageQueue.peekNext() == nil
        }
    }

    func testQueuedMessageStaysQueuedWhileRuntimeStillBusy() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.activateViewLifecycle()
        await fixture.agentsManager.setStatus(.busy, for: fixture.conversation.id)
        await fixture.agentsManager.enqueueRefreshStatus(.busy)
        fixture.viewModel.turnState.beginTurn()

        try await fixture.viewModel.queueOrSend("Follow-up")
        fixture.viewModel.handleTurnCompleted()
        try await Task.sleep(nanoseconds: 50_000_000)

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, [])
        XCTAssertEqual(fixture.viewModel.messageQueue.peekNext()?.text, "Follow-up")
    }
}

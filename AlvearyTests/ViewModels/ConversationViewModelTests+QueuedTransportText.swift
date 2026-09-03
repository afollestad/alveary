import Foundation
import XCTest

@testable import Alveary

/// The drain keeps whatever transport text a message was queued with unless it is plan-revision
/// guidance that went stale. Before this, only plan guidance survived the wait: an app shot's
/// hidden context, or any other provider-only text, reached the provider as the visible text.
@MainActor
extension ConversationViewModelTests {
    func testDrainedQueuedMessageKeepsTransportTextThatIsNotPlanGuidance() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.activateViewLifecycle()
        await fixture.agentsManager.setStatus(.busy, for: fixture.conversation.id)
        fixture.viewModel.turnState.beginTurn()
        fixture.viewModel.messageQueue.enqueue("Visible text", transportText: "Transport text")

        await fixture.agentsManager.setStatus(.idle, for: fixture.conversation.id)
        fixture.viewModel.handleTurnCompleted()

        try await waitUntil("queued message drained with its transport text") {
            await fixture.agentsManager.sentMessages() == ["Transport text"] &&
                fixture.viewModel.messageQueue.peekNext() == nil
        }
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Visible text"])
    }
}

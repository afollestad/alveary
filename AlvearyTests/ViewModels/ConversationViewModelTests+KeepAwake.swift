import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testOutboundSetupKeepsMacAwakeUntilCancelled() async throws {
        let fixture = try ConversationViewModelTestFixture(
            threadName: "New thread",
            useWorktree: true,
            hasCompletedInitialSetup: false,
            pausesWorktreeCreate: true
        )
        let source = KeepAwakeActivitySource.outboundConversationWork(conversationId: fixture.conversation.id)

        let sendTask = Task {
            try await fixture.viewModel.queueOrSend("Start work")
        }

        try await waitUntil("expected initial setup to begin creating a worktree") {
            fixture.viewModel.setupPhase == .creatingWorktree
        }
        XCTAssertTrue(fixture.keepAwakeService.isActive(source))

        await fixture.viewModel.cancel()

        do {
            try await sendTask.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // expected
        }
        XCTAssertFalse(fixture.keepAwakeService.isActive(source))
    }
}

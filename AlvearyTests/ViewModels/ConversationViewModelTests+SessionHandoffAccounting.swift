import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testAutomaticSessionHandoffUsesCodexCachedInputAccounting() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")

        fixture.viewModel.handleEvent(.tokens(
            input: 100,
            output: 5,
            cacheRead: 100,
            isError: false,
            stopReason: "end_turn",
            durationMs: 10,
            costUsd: 0.01,
            contextWindowSize: 200,
            permissionDenials: []
        ))

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertFalse(fixture.viewModel.state.isHandingOffSession)
        XCTAssertFalse(fixture.viewModel.state.isAwaitingHandoffSteering)
        XCTAssertFalse(fixture.viewModel.state.isAutomaticSessionHandoffPending)
        XCTAssertTrue(sentMessages.isEmpty)
    }
}

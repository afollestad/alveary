import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testNoninitialStartCleansUpProviderThatFinishesSpawningAfterCancellation() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false
        )
        await fixture.agentsManager.failDestroyWhenCurrentTaskIsCancelled()
        await fixture.agentsManager.pauseNextSpawn()
        let config = try fixture.viewModel.makeSpawnConfig()

        let start = Task {
            try await fixture.viewModel.startAgent(config: config)
        }
        await fixture.agentsManager.waitUntilSpawnEntered()
        start.cancel()
        await fixture.agentsManager.waitUntilSpawnCancellationObserved()
        await fixture.agentsManager.resumePausedSpawn()

        do {
            try await start.value
            XCTFail("Expected the cancelled provider start to throw")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        let destroyCalls = await fixture.agentsManager.destroyCalls()
        let runtimeIsRunning = await fixture.agentsManager.isRunning(conversationId: fixture.conversation.id)
        let subscribeCalls = await fixture.agentsManager.subscribeCalls()
        XCTAssertEqual(destroyCalls, [fixture.conversation.id])
        XCTAssertFalse(runtimeIsRunning)
        XCTAssertNil(fixture.viewModel.state.liveSessionConfig)
        XCTAssertEqual(subscribeCalls, 0)
    }
}

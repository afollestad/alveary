import XCTest

@testable import Alveary

@MainActor
extension ConversationControllerRegistryTests {
    func testTurnStartedDuringFailingFlushAutomaticallyRetriesOnce() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let flushGate = ControllerFailingFlushGate()
        let maintenance = ControllerMaintenanceRecorder()
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in try await flushGate.flush() },
            suspendRuntime: { _ in maintenance.record("suspend") }
        )
        let lease = registry.makeBackgroundLease(for: fixture.conversation)
        let key = lease.key
        lease.activate()
        var outcomes = lease.outcomes().makeAsyncIterator()
        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()
        let firstActive = await outcomes.next()
        fixture.viewModel.state.endTurn()
        try await waitUntil("expected first terminal flush to start") { flushGate.flushCallCount == 1 }

        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()
        await Task.yield()
        flushGate.open()

        let failed = await outcomes.next()
        let secondActive = await outcomes.next()
        XCTAssertEqual(failed?.turn, firstActive?.turn)
        guard case .terminal(.failed) = failed?.state else {
            XCTFail("Expected the first turn to report its flush failure")
            return
        }
        XCTAssertEqual(secondActive?.state, .active)
        XCTAssertNotEqual(secondActive?.turn, firstActive?.turn)
        try await waitUntil("expected one automatic retry for the already-started turn") {
            flushGate.flushCallCount == 2
        }
        await Task.yield()
        XCTAssertEqual(flushGate.flushCallCount, 2)

        lease.release()
        fixture.viewModel.state.endTurn()
        let secondTerminal = await outcomes.next()
        XCTAssertEqual(secondTerminal?.turn, secondActive?.turn)
        XCTAssertEqual(secondTerminal?.state, .terminal(.succeeded))
        try await waitUntil("expected second turn maintenance and suspension") {
            flushGate.flushCallCount == 3 &&
                maintenance.values == ["suspend"] &&
                registry.controller(for: key) == nil
        }
    }
}

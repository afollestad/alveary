import XCTest

@testable import Alveary

@MainActor
extension ConversationControllerRegistryTests {
    func testLiveBackgroundTasksRetainControllerAndRuntimeUntilCountReturnsToZero() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true
        )
        let recorder = ControllerMaintenanceRecorder()
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in recorder.record("flush") },
            suspendRuntime: { _ in recorder.record("suspend") },
            runtimeIsSuspended: { _ in true }
        )
        let lease = registry.makeBackgroundLease(for: fixture.conversation)
        let key = lease.key
        lease.activate()
        var outcomes = lease.outcomes().makeAsyncIterator()
        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()
        let active = await outcomes.next()
        XCTAssertEqual(active?.state, .active)

        fixture.viewModel.state.liveBackgroundTaskCount = 2
        fixture.viewModel.state.endTurn()
        lease.release()
        try await waitUntil("expected the terminal boundary to flush without suspending") {
            recorder.values == ["flush"]
        }
        await Task.yield()
        XCTAssertIdentical(registry.controller(for: key), fixture.viewModel)
        XCTAssertEqual(recorder.values, ["flush"])

        fixture.viewModel.state.liveBackgroundTaskCount = 0
        try await waitUntil("expected the drained task count to allow suspension") {
            recorder.values == ["flush", "flush", "suspend"] && registry.controller(for: key) == nil
        }
    }

    func testDeferredLeaseFinalizationWaitsWhileBackgroundTasksAreLive() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let recorder = ControllerMaintenanceRecorder()
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in recorder.record("flush") },
            suspendRuntime: { _ in recorder.record("suspend") },
            runtimeIsSuspended: { _ in true }
        )
        let lease = registry.makeBackgroundLease(
            for: fixture.conversation,
            defersAutomaticSuspension: true
        )
        let key = lease.key
        lease.activate()
        fixture.viewModel.state.liveBackgroundTaskCount = 1

        do {
            try await lease.finalizeDeferredSuspension()
            XCTFail("Expected finalization to wait for live background tasks")
        } catch DeferredControllerFinalizationError.controllerNotQuiescent {
        }
        XCTAssertFalse(recorder.values.contains("suspend"))
        XCTAssertIdentical(registry.controller(for: key), fixture.viewModel)

        fixture.viewModel.state.liveBackgroundTaskCount = 0
        try await lease.finalizeDeferredSuspension()

        XCTAssertEqual(recorder.values.filter { $0 == "suspend" }, ["suspend"])
        XCTAssertNil(registry.controller(for: key))
    }
}

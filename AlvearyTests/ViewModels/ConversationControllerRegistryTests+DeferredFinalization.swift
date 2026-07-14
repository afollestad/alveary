import XCTest

@testable import Alveary

@MainActor
extension ConversationControllerRegistryTests {
    func testDeferredLeaseFinalizationCoalescesAndAwaitsOneFlushAndSuspension() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let recorder = ControllerMaintenanceRecorder()
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in recorder.record("flush") },
            suspendRuntime: { _ in recorder.record("suspend") },
            runtimeIsSuspended: { _ in
                recorder.record("verify")
                return true
            }
        )
        let lease = registry.makeBackgroundLease(
            for: fixture.conversation,
            defersAutomaticSuspension: true
        )
        let key = lease.key
        lease.activate()

        let first = Task { try await lease.finalizeDeferredSuspension() }
        let second = Task { try await lease.finalizeDeferredSuspension() }
        try await first.value
        try await second.value

        XCTAssertEqual(recorder.values, ["flush", "suspend", "verify"])
        XCTAssertNil(registry.controller(for: key))
        XCTAssertFalse(fixture.viewModel.hasActivatedBackgroundLifecycle)
    }

    func testDeferredLeaseRetriesFailedTerminalFlushBeforePublishingProviderResult() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let recorder = ControllerMaintenanceRecorder(flushFailuresRemaining: 1)
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in try recorder.flush() },
            suspendRuntime: { _ in recorder.record("suspend") },
            runtimeIsSuspended: { _ in true },
            terminalFlushRetryWait: {}
        )
        let lease = registry.makeBackgroundLease(
            for: fixture.conversation,
            defersAutomaticSuspension: true
        )
        let key = lease.key
        lease.activate()
        var outcomes = lease.outcomes().makeAsyncIterator()
        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()
        _ = await outcomes.next()
        fixture.viewModel.state.endTurn()

        let terminal = await outcomes.next()
        guard case .terminal(.succeeded) = terminal?.state else {
            XCTFail("Expected the provider terminal after the flush retry")
            return
        }

        try await lease.finalizeDeferredSuspension()

        XCTAssertEqual(recorder.values, ["flush", "flush", "flush", "suspend"])
        XCTAssertNil(registry.controller(for: key))
        XCTAssertNil(fixture.viewModel.lastTurnError)
    }

    func testDeferredLeaseRetriesStatusLagUntilRuntimeIsActuallySuspended() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let recorder = ControllerMaintenanceRecorder()
        var verificationAttempts = 0
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in recorder.record("flush") },
            suspendRuntime: { _ in recorder.record("suspend") },
            runtimeIsSuspended: { _ in
                verificationAttempts += 1
                recorder.record("verify")
                return verificationAttempts == 2
            },
            terminalFlushRetryWait: { recorder.record("wait") }
        )
        let lease = registry.makeBackgroundLease(
            for: fixture.conversation,
            defersAutomaticSuspension: true
        )
        let key = lease.key
        lease.activate()

        try await lease.finalizeDeferredSuspension()

        XCTAssertEqual(
            recorder.values,
            ["flush", "suspend", "verify", "wait", "suspend", "verify"]
        )
        XCTAssertNil(registry.controller(for: key))
        XCTAssertFalse(fixture.viewModel.hasActivatedBackgroundLifecycle)
    }
}

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
            suspendRuntime: { _ in maintenance.record("suspend") },
            runtimeIsSuspended: { _ in true }
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

    func testTerminalMaintenanceRetriesStatusLagBeforeEviction() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let maintenance = ControllerMaintenanceRecorder()
        let retryGate = ControllerMaintenanceWaitGate()
        var verificationAttempts = 0
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in maintenance.record("flush") },
            suspendRuntime: { _ in maintenance.record("suspend") },
            runtimeIsSuspended: { _ in
                verificationAttempts += 1
                maintenance.record("verify")
                return verificationAttempts == 2
            },
            terminalFlushRetryWait: {
                maintenance.record("wait")
                await retryGate.wait()
            }
        )
        let lease = registry.makeBackgroundLease(for: fixture.conversation)
        let key = lease.key
        lease.activate()
        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()
        lease.release()
        fixture.viewModel.state.endTurn()

        try await waitUntil("expected runtime suspension verification to wait for status catch-up") {
            retryGate.waitCallCount == 1
        }
        XCTAssertEqual(maintenance.values, ["flush", "suspend", "verify", "wait"])
        XCTAssertIdentical(registry.controller(for: key), fixture.viewModel)
        XCTAssertTrue(fixture.viewModel.hasActivatedBackgroundLifecycle)

        retryGate.open()

        try await waitUntil("expected verified runtime suspension before eviction") {
            maintenance.values == ["flush", "suspend", "verify", "wait", "suspend", "verify"] &&
                registry.controller(for: key) == nil
        }
        XCTAssertFalse(fixture.viewModel.hasActivatedBackgroundLifecycle)
    }

    func testQuiescenceMaintenanceRetriesStatusLagBeforeEviction() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let flushGate = ControllerFlushGate()
        let maintenance = ControllerMaintenanceRecorder()
        var verificationAttempts = 0
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in
                await flushGate.flush()
                maintenance.record("flush")
            },
            suspendRuntime: { _ in maintenance.record("suspend") },
            runtimeIsSuspended: { _ in
                verificationAttempts += 1
                maintenance.record("verify")
                return verificationAttempts == 2
            },
            terminalFlushRetryWait: { maintenance.record("wait") }
        )
        let lease = registry.makeBackgroundLease(for: fixture.conversation)
        let key = lease.key
        lease.activate()
        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()
        lease.release()
        fixture.viewModel.state.endTurn()
        try await waitUntil("expected terminal flush to start") { flushGate.flushCallCount == 1 }
        fixture.viewModel.saveTask = Task { try? await Task.sleep(for: .seconds(5)) }
        flushGate.open()

        try await waitUntil("expected persistence to defer runtime suspension") {
            maintenance.values == ["flush"]
        }
        fixture.viewModel.saveTask?.cancel()
        fixture.viewModel.saveTask = nil

        try await waitUntil("expected quiescence maintenance to verify suspension") {
            maintenance.values == [
                "flush", "flush", "suspend", "verify", "wait", "suspend", "verify"
            ] && registry.controller(for: key) == nil
        }
    }

    func testNewTurnDuringSuspensionRetryKeepsControllerUntilNextTerminal() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let maintenance = ControllerMaintenanceRecorder()
        let retryGate = ControllerMaintenanceWaitGate()
        var verificationAttempts = 0
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in maintenance.record("flush") },
            suspendRuntime: { _ in maintenance.record("suspend") },
            runtimeIsSuspended: { _ in
                verificationAttempts += 1
                maintenance.record("verify")
                return verificationAttempts == 2
            },
            terminalFlushRetryWait: {
                maintenance.record("wait")
                await retryGate.wait()
            }
        )
        let lease = registry.makeBackgroundLease(for: fixture.conversation)
        let key = lease.key
        lease.activate()
        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()
        lease.release()
        fixture.viewModel.state.endTurn()
        try await waitUntil("expected suspension retry wait") { retryGate.waitCallCount == 1 }

        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()
        retryGate.open()

        try await waitUntil("expected the active turn to cancel suspension maintenance") {
            registry.controller(for: key) === fixture.viewModel &&
                maintenance.values == ["flush", "suspend", "verify", "wait"]
        }
        fixture.viewModel.state.endTurn()

        try await waitUntil("expected the next terminal to complete verified suspension") {
            maintenance.values == [
                "flush", "suspend", "verify", "wait", "flush", "suspend", "verify"
            ] && registry.controller(for: key) == nil
        }
    }

    func testInvalidationDuringSuspensionExitsWithoutVerificationOrReactivation() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let maintenance = ControllerMaintenanceRecorder()
        let suspensionGate = ControllerMaintenanceWaitGate()
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in maintenance.record("flush") },
            suspendRuntime: { _ in
                maintenance.record("suspend")
                await suspensionGate.wait()
            },
            runtimeIsSuspended: { _ in
                maintenance.record("verify")
                return true
            }
        )
        let lease = registry.makeBackgroundLease(for: fixture.conversation)
        let key = lease.key
        lease.activate()
        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()
        lease.release()
        fixture.viewModel.state.endTurn()
        try await waitUntil("expected suspension to start") { suspensionGate.waitCallCount == 1 }

        registry.invalidate(for: key)
        suspensionGate.open()
        await Task.yield()

        XCTAssertEqual(maintenance.values, ["flush", "suspend"])
        XCTAssertNil(registry.controller(for: key))
        XCTAssertFalse(fixture.viewModel.hasActivatedBackgroundLifecycle)
    }
}

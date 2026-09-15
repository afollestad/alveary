import SwiftData
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

    func testDeferredLeaseRetriesFailedTerminalFlushBeforePublishingHarnessResult() async throws {
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
            XCTFail("Expected the harness terminal after the flush retry")
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

    func testDeferredLeaseCannotSuspendWhileNextApprovalIsRecovering() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let gate = ControllerApprovalRecoveryGate()
        try installApprovalRecovery(in: fixture, gate: gate)
        let previousApproval = ToolApprovalRequest(sessionId: "session", toolUseId: "previous", toolName: "Read", toolInput: "{}")
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: previousApproval, status: .pending)
        var suspensions = 0
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in },
            suspendRuntime: { _ in suspensions += 1 },
            runtimeIsSuspended: { _ in true }
        )
        let lease = registry.makeBackgroundLease(for: fixture.conversation, defersAutomaticSuspension: true)
        lease.activate()
        fixture.viewModel.state.pendingToolApproval = nil
        fixture.viewModel.hydratePendingToolApprovalIfNeeded()
        try await waitUntil("expected next approval recovery") { gate.hasEntered }

        do {
            try await lease.finalizeDeferredSuspension()
            XCTFail("Approval recovery must prevent finalization")
        } catch {
            XCTAssertTrue(error is DeferredControllerFinalizationError)
        }
        XCTAssertEqual(suspensions, 0)
        XCTAssertEqual(registry.currentOutcome(for: lease.key)?.state, .waitingForApproval(interactionID: "previous"))

        let recovery = fixture.viewModel.toolApprovalRestoreTask
        gate.open()
        await recovery?.value
        try await lease.finalizeDeferredSuspension()

        XCTAssertEqual(suspensions, 1)
        XCTAssertNil(registry.controller(for: lease.key))
    }

    func testApprovalRecoveryRetainsReleasedControllerAndObservesCompletion() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let gate = ControllerApprovalRecoveryGate()
        try installApprovalRecovery(in: fixture, gate: gate)
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in },
            suspendRuntime: { _ in },
            runtimeIsSuspended: { _ in true }
        )
        let lease = registry.makeViewLease(for: fixture.conversation)
        lease.activate()
        try await waitUntil("expected approval recovery") { gate.hasEntered }
        lease.release()

        XCTAssertIdentical(registry.controller(for: lease.key), fixture.viewModel)
        XCTAssertTrue(fixture.viewModel.hasActivatedBackgroundLifecycle)
        XCTAssertTrue(fixture.viewModel.state.isRestoringToolApproval)
        gate.open()

        try await waitUntil("expected recovered idle controller eviction") { registry.controller(for: lease.key) == nil }
        XCTAssertFalse(fixture.viewModel.state.isRestoringToolApproval)
    }

    private func installApprovalRecovery(in fixture: ConversationViewModelTestFixture, gate: ControllerApprovalRecoveryGate) throws {
        fixture.context.insert(ConversationEventRecord(
            conversationId: fixture.conversation.id, type: "tool_approval", content: "session",
            toolId: "recovering", toolName: "Bash", toolInput: "{}", conversation: fixture.conversation
        ))
        try fixture.context.save()
        fixture.viewModel.readToolApprovalTranscript = { _ in
            await gate.wait()
            return .approved
        }
    }
}

@MainActor
private final class ControllerApprovalRecoveryGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var hasEntered = false

    func wait() async {
        hasEntered = true
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

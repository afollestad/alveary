import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskRunExecutorTests {
    // swiftlint:disable:next function_body_length
    func testSecondaryConversationCannotStartWhileTerminalRunIsStillFinalizing() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let run = try attachRun(to: fixture, status: .preparing)
        let secondaryConversation = Conversation(
            id: "scheduled-secondary",
            title: "Follow-up",
            provider: "claude",
            isMain: false,
            displayOrder: 1,
            thread: fixture.thread
        )
        fixture.thread.conversations.append(secondaryConversation)
        fixture.context.insert(secondaryConversation)
        try fixture.context.save()
        let secondaryViewModel = ConversationViewModel(
            conversation: secondaryConversation,
            agentsManager: fixture.agentsManager,
            runtimeStore: fixture.runtimeStore,
            keepAwakeService: fixture.keepAwakeService,
            modelContext: fixture.context,
            settingsService: fixture.settingsService,
            worktreeManager: fixture.worktreeManager,
            providerSetup: fixture.providerSetup,
            contextWindowCache: fixture.contextWindowCache
        )
        let suspensionGate = ScheduledRuntimeSuspensionGate()
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in },
            suspendRuntime: { _ in await suspensionGate.suspend() },
            runtimeIsSuspended: { _ in true }
        )
        let executor = DefaultScheduledTaskRunExecutor(
            modelContext: fixture.context,
            controllerRegistry: registry,
            notificationManager: makeNotificationManager(fixture: fixture),
            startAutomatedTurn: { viewModel, _ in
                viewModel.markVisibleTurnStarted()
                viewModel.turnState.beginTurn()
            }
        )
        let execution = Task {
            try await executor.execute(makeMaterialization(run: run, fixture: fixture))
        }
        try await waitUntil("expected scheduled run to start") {
            run.status == .running
        }

        fixture.viewModel.state.endTurn()
        await suspensionGate.waitUntilEntered()

        XCTAssertEqual(run.status, .success)
        XCTAssertTrue(run.requiresFinalizationRecovery)
        XCTAssertTrue(secondaryViewModel.defersOrdinaryScheduledOutbound)
        do {
            try await secondaryViewModel.send("Do not start during scheduled finalization.")
            XCTFail("Expected the secondary conversation to wait for scheduled finalization")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Wait for the scheduled task's initial turn to finish"
            )
        }
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)

        suspensionGate.release()
        let result = try await execution.value

        XCTAssertEqual(result, .succeeded)
        XCTAssertFalse(run.requiresFinalizationRecovery)
        XCTAssertFalse(secondaryViewModel.defersOrdinaryScheduledOutbound)
    }

    func testControllerFlushRetryPreservesSuccessfulProviderResult() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let run = try attachRun(to: fixture, status: .preparing)
        let retryGate = ControllerFlushRetryGate()
        let flushRecorder = InitialControllerFlushRecorder()
        let suspension = ScheduledExecutionSuspensionRecorder(conversation: fixture.conversation)
        let notifications = ScheduledExecutionNotificationRecorder()
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in try flushRecorder.flush() },
            suspendRuntime: { _ in suspension.recordSuspension() },
            runtimeIsSuspended: { _ in true },
            terminalFlushRetryWait: { await retryGate.wait() }
        )
        let executor = DefaultScheduledTaskRunExecutor(
            modelContext: fixture.context,
            controllerRegistry: registry,
            notificationManager: notifications,
            startAutomatedTurn: { viewModel, _ in
                viewModel.markVisibleTurnStarted()
                viewModel.turnState.beginTurn()
            }
        )
        let execution = Task { try await executor.execute(makeMaterialization(run: run, fixture: fixture)) }
        try await waitUntil("expected scheduled run to start") { run.status == .running }

        fixture.viewModel.state.endTurn()
        try await waitUntil("expected controller flush retry") { retryGate.waitCount == 1 }

        XCTAssertEqual(run.status, .running)
        XCTAssertFalse(fixture.conversation.isUnread)
        XCTAssertTrue(notifications.handledEvents.isEmpty)
        XCTAssertTrue(suspension.observations.isEmpty)

        retryGate.open()
        let result = try await execution.value

        XCTAssertEqual(result, .succeeded)
        XCTAssertEqual(run.status, .success)
        XCTAssertTrue(fixture.conversation.isUnread)
        XCTAssertEqual(flushRecorder.callCount, 3)
        XCTAssertEqual(notifications.handledEvents.map(\.event), [.stop(message: nil)])
        XCTAssertEqual(suspension.observations.count, 1)
    }

    // swiftlint:disable:next function_body_length
    func testLateApprovalDuringSuspensionIsSupersededBeforeDeferredLeaseReleases() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let run = try attachRun(to: fixture, status: .preparing)
        let retryGate = ControllerFlushRetryGate()
        let lateApproval = makeToolApproval()
        let key = ConversationControllerKey(conversation: fixture.conversation)
        var suspensionCount = 0
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { try await $0.flushPendingSaveNow() },
            suspendRuntime: { viewModel in
                suspensionCount += 1
                if suspensionCount == 1 {
                    viewModel.handleEvent(.toolApprovalRequested(lateApproval))
                }
            },
            runtimeIsSuspended: { _ in
                await fixture.agentsManager.cancelCalls().isEmpty == false
            }
        )
        let executor = DefaultScheduledTaskRunExecutor(
            modelContext: fixture.context,
            controllerRegistry: registry,
            notificationManager: makeNotificationManager(fixture: fixture),
            startAutomatedTurn: { viewModel, _ in
                viewModel.markVisibleTurnStarted()
                viewModel.turnState.beginTurn()
            },
            persistenceRetryWait: {
                if suspensionCount == 1, retryGate.waitCount == 0 {
                    await retryGate.wait()
                } else {
                    await Task.yield()
                }
            }
        )
        let execution = Task {
            try await executor.execute(makeMaterialization(run: run, fixture: fixture))
        }
        try await waitUntil("expected scheduled run to start") { run.status == .running }

        fixture.viewModel.state.endTurn()
        try await waitUntil("expected late interaction to block the first finalization") {
            retryGate.waitCount == 1
        }
        var retainedOutcomes = registry.outcomes(for: key).makeAsyncIterator()
        let waitingOutcome = await retainedOutcomes.next()
        let approvalRecordBeforeRetry = try XCTUnwrap(fixture.records(type: "tool_approval").first {
            $0.toolId == lateApproval.toolUseId
        })
        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertEqual(
            approvalRecordBeforeRetry.toolApprovalStatus,
            ToolApprovalStatus.superseded.rawValue
        )
        guard case .waitingForApproval = waitingOutcome?.state else {
            return XCTFail("Expected the late approval to be the current controller outcome")
        }
        XCTAssertIdentical(
            registry.controller(for: key),
            fixture.viewModel
        )

        retryGate.open()
        let result = try await execution.value

        let approvalRecord = try XCTUnwrap(fixture.records(type: "tool_approval").first {
            $0.toolId == lateApproval.toolUseId
        })
        let terminalizedOutcome = await retainedOutcomes.next()
        var replayedOutcomes = registry.outcomes(for: key).makeAsyncIterator()
        let replayedOutcome = await replayedOutcomes.next()
        XCTAssertEqual(result, .succeeded)
        XCTAssertEqual(run.status, .success)
        XCTAssertEqual(suspensionCount, 2)
        XCTAssertEqual(approvalRecord.toolApprovalStatus, ToolApprovalStatus.superseded.rawValue)
        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        let discardCancelCalls = await fixture.agentsManager.cancelCalls()
        XCTAssertEqual(discardCancelCalls, [fixture.conversation.id])
        XCTAssertNil(registry.controller(for: key))
        XCTAssertEqual(terminalizedOutcome?.state, .interrupted)
        XCTAssertEqual(replayedOutcome?.state, .interrupted)
    }

    func testInitialSetupCancellationDefersManualOutboundUntilScheduledSuspensionFinishes() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        let run = try XCTUnwrap(fixture.thread.scheduledTaskRun)
        let providerStartGate = ScheduledFinalizationProviderStartGate()
        let suspensionGate = ScheduledRuntimeSuspensionGate()
        await fixture.providerSetup.setPrepareForSpawnHook {
            await providerStartGate.waitForRelease()
        }
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in },
            suspendRuntime: { _ in await suspensionGate.suspend() },
            runtimeIsSuspended: { _ in true }
        )
        let executor = DefaultScheduledTaskRunExecutor(
            modelContext: fixture.context,
            controllerRegistry: registry,
            notificationManager: makeNotificationManager(fixture: fixture)
        )
        let execution = Task {
            try await executor.execute(makeMaterialization(run: run, fixture: fixture))
        }
        await providerStartGate.waitUntilEntered()

        let stop = Task { @MainActor in
            try await executor.stop(runID: run.persistentModelID)
        }
        await providerStartGate.waitUntilCancellationObserved()
        await providerStartGate.release()
        try await stop.value
        await suspensionGate.waitUntilEntered()

        XCTAssertEqual(run.status, .interrupted)
        XCTAssertTrue(fixture.viewModel.state.isAutomatedScheduledRunActive)
        do {
            try await fixture.viewModel.send("Do not start before scheduled suspension finishes.")
            XCTFail("Expected manual outbound to wait for scheduled finalization")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Wait for the scheduled task's initial turn to finish"
            )
        }
        let spawnCallsBeforeFinalization = await fixture.agentsManager.spawnCalls()
        XCTAssertTrue(spawnCallsBeforeFinalization.isEmpty)

        suspensionGate.release()
        let result = try await execution.value

        XCTAssertEqual(result, .interrupted)
        XCTAssertFalse(fixture.viewModel.state.isAutomatedScheduledRunActive)
    }
}

@MainActor
private final class ControllerFlushRetryGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var waitCount = 0

    func wait() async {
        waitCount += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class InitialControllerFlushRecorder {
    private(set) var callCount = 0

    func flush() throws {
        callCount += 1
        if callCount == 1 {
            throw ScheduledTaskExecutorTestError.saveFailed
        }
    }
}

private actor ScheduledFinalizationProviderStartGate {
    private var entered = false
    private var cancellationObserved = false
    private var released = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var cancellationContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func waitForRelease() async {
        entered = true
        enteredContinuation?.resume()
        enteredContinuation = nil
        guard !released else {
            return
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        } onCancel: {
            Task { await self.recordCancellation() }
        }
    }

    func waitUntilEntered() async {
        guard !entered else {
            return
        }
        await withCheckedContinuation { continuation in
            enteredContinuation = continuation
        }
    }

    func waitUntilCancellationObserved() async {
        guard !cancellationObserved else {
            return
        }
        await withCheckedContinuation { continuation in
            cancellationContinuation = continuation
        }
    }

    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    private func recordCancellation() {
        cancellationObserved = true
        cancellationContinuation?.resume()
        cancellationContinuation = nil
    }
}

@MainActor
private final class ScheduledRuntimeSuspensionGate {
    private var entered = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        entered = true
        enteredContinuation?.resume()
        enteredContinuation = nil
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilEntered() async {
        guard !entered else {
            return
        }
        await withCheckedContinuation { continuation in
            enteredContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

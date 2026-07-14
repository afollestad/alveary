import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskRunExecutorTests {
    func testConcurrentStopCleanupBlocksManualFollowUpUntilDeferredRuntimeDiscardFinishes() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        let run = try XCTUnwrap(fixture.thread.scheduledTaskRun)
        let joinObserver = ScheduledCancellationJoinObserver()
        let executor = makeExecutor(fixture: fixture, joinObserver: joinObserver)
        let executionResult = ScheduledExecutionResultBox()
        let execution = startExecution(executor, fixture: fixture, result: executionResult)
        defer { execution.cancel() }
        try await enterInactiveDeferredInteraction(run: run, fixture: fixture)
        await fixture.agentsManager.pauseNextDeferredDiscard()

        execution.cancel()
        await joinObserver.waitUntilEntered()
        await fixture.agentsManager.waitUntilDeferredDiscardEntered()
        let stop = Task { @MainActor in
            try await executor.stop(runID: run.persistentModelID)
        }
        await Task.yield()
        await assertManualFollowUpBlocked(
            fixture: fixture,
            executionResult: executionResult,
            joinObserver: joinObserver
        )

        await fixture.agentsManager.resumeDeferredDiscard()
        try await stop.value
        try await waitUntil("expected scheduled execution to finalize after cleanup") {
            executionResult.hasResolved && joinObserver.hasCompleted
        }
        try await assertManualFollowUpStartsAfterCleanup(
            fixture: fixture,
            run: run,
            executionResult: executionResult
        )
    }

    func testDelayedCancellationCleanupDoesNotCancelOrdinaryFollowUpAfterFinalization() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        let run = try XCTUnwrap(fixture.thread.scheduledTaskRun)
        let cleanupGate = ScheduledCancellationCleanupGate()
        defer { cleanupGate.release() }
        let executor = makeExecutor(fixture: fixture, cleanupGate: cleanupGate)
        let materialization = try makeMaterialization(fixture: fixture)
        let executionResult = ScheduledExecutionResultBox()
        let execution = Task {
            do {
                executionResult.resolve(.success(try await executor.execute(materialization)))
            } catch {
                executionResult.resolve(.failure(error))
            }
        }
        defer { execution.cancel() }
        try await waitUntil("expected scheduled execution to become active") {
            run.status == .running && fixture.viewModel.turnState.isActive
        }

        execution.cancel()
        try await waitUntil("expected delayed cancellation cleanup to enter") {
            cleanupGate.hasEntered
        }
        fixture.viewModel.state.lastTurnInterrupted = true
        fixture.viewModel.state.isCancellingTurn = false
        fixture.viewModel.state.endTurn()

        try await waitUntil("expected scheduled execution to finalize") {
            executionResult.hasResolved
        }
        let result = try executionResult.get()
        XCTAssertEqual(result, .interrupted)
        XCTAssertEqual(run.status, .interrupted)
        XCTAssertFalse(fixture.viewModel.state.isAutomatedScheduledRunActive)
        let scheduledCancelCalls = await fixture.agentsManager.cancelCalls()

        try await fixture.viewModel.send("Continue manually.")
        XCTAssertTrue(fixture.viewModel.turnState.isActive)

        cleanupGate.release()
        try await waitUntil("expected delayed cancellation cleanup to complete") {
            cleanupGate.hasCompleted
        }

        await assertOrdinaryFollowUpRemainsActive(
            fixture,
            expectedCancelCallCount: scheduledCancelCalls.count
        )
    }

    private func makeMaterialization(
        fixture: ConversationViewModelTestFixture
    ) throws -> ScheduledTaskRunMaterialization {
        let run = try XCTUnwrap(fixture.thread.scheduledTaskRun)
        let workspace = try XCTUnwrap(fixture.thread.taskWorkspaceDescriptor)
        return ScheduledTaskRunMaterialization(
            runID: run.persistentModelID,
            threadID: fixture.thread.persistentModelID,
            conversationID: fixture.conversation.id,
            prompt: run.promptSnapshot,
            workspace: workspace
        )
    }

    private func startExecution(
        _ executor: DefaultScheduledTaskRunExecutor,
        fixture: ConversationViewModelTestFixture,
        result: ScheduledExecutionResultBox
    ) -> Task<Void, Never> {
        Task {
            do {
                result.resolve(.success(try await executor.execute(makeMaterialization(fixture: fixture))))
            } catch {
                result.resolve(.failure(error))
            }
        }
    }

    private func assertManualFollowUpBlocked(
        fixture: ConversationViewModelTestFixture,
        executionResult: ScheduledExecutionResultBox,
        joinObserver: ScheduledCancellationJoinObserver
    ) async {
        let discardCalls = await fixture.agentsManager.deferredDiscardCalls()
        XCTAssertEqual(discardCalls, [fixture.conversation.id])
        XCTAssertFalse(joinObserver.hasCompleted)
        XCTAssertFalse(executionResult.hasResolved)
        XCTAssertTrue(fixture.viewModel.state.isAutomatedScheduledRunActive)
        do {
            try await fixture.viewModel.send("Do not start while scheduled cleanup is pending.")
            XCTFail("Expected manual outbound to wait for scheduled cleanup")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Wait for the scheduled task's initial turn to finish"
            )
        }
        XCTAssertNil(fixture.viewModel.state.messageQueue.peekNext())
    }

    private func assertManualFollowUpStartsAfterCleanup(
        fixture: ConversationViewModelTestFixture,
        run: ScheduledTaskRun,
        executionResult: ScheduledExecutionResultBox
    ) async throws {
        XCTAssertEqual(try executionResult.get(), .interrupted)
        XCTAssertEqual(run.status, .interrupted)
        XCTAssertFalse(fixture.viewModel.state.isAutomatedScheduledRunActive)
        let terminalDiscardCalls = await fixture.agentsManager.deferredDiscardCalls()
        XCTAssertEqual(terminalDiscardCalls, [fixture.conversation.id])

        try await fixture.viewModel.send("Continue manually.")
        XCTAssertTrue(fixture.viewModel.turnState.isActive)
        let followUpDiscardCalls = await fixture.agentsManager.deferredDiscardCalls()
        XCTAssertEqual(followUpDiscardCalls, [fixture.conversation.id])
    }

    private func enterInactiveDeferredInteraction(
        run: ScheduledTaskRun,
        fixture: ConversationViewModelTestFixture
    ) async throws {
        try await waitUntil("expected automated scheduled turn to start") {
            run.status == .running && fixture.viewModel.turnState.isActive
        }
        let approval = ToolApprovalRequest(
            sessionId: "scheduled-session",
            toolUseId: "scheduled-question",
            toolName: "AskUserQuestion",
            toolInput: #"{"questions":[{"question":"Continue?","options":[{"label":"Yes","description":"Continue"}]}]}"#
        )
        fixture.viewModel.handleEvent(.toolCall(
            id: approval.toolUseId,
            name: approval.toolName,
            input: approval.toolInput,
            parentToolUseId: nil,
            callerAgent: nil
        ))
        fixture.viewModel.handleEvent(.toolApprovalRequested(approval))
        fixture.viewModel.handleEvent(.tokens(
            input: 1,
            output: 1,
            cacheRead: 0,
            isError: false,
            stopReason: "tool_deferred",
            durationMs: 10,
            costUsd: 0,
            permissionDenials: []
        ))
        try await waitUntil("expected inactive deferred scheduled interaction") {
            run.status == .waiting &&
                fixture.viewModel.state.hasDeferredControllerTerminalBoundary &&
                !fixture.viewModel.turnState.isActive
        }
    }

    private func makeExecutor(
        fixture: ConversationViewModelTestFixture,
        cleanupGate: ScheduledCancellationCleanupGate
    ) -> DefaultScheduledTaskRunExecutor {
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            suspendRuntime: { _ in },
            runtimeIsSuspended: { _ in true }
        )
        return DefaultScheduledTaskRunExecutor(
            modelContext: fixture.context,
            controllerRegistry: registry,
            notificationManager: makeNotificationManager(fixture: fixture),
            cancellationHandlerAction: { execution in
                await cleanupGate.waitForRelease()
                execution.cancelProviderTasks()
                await execution.cancelConversationActivity()
                cleanupGate.recordCompletion()
            }
        )
    }

    private func makeExecutor(
        fixture: ConversationViewModelTestFixture,
        joinObserver: ScheduledCancellationJoinObserver
    ) -> DefaultScheduledTaskRunExecutor {
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            suspendRuntime: { _ in },
            runtimeIsSuspended: { _ in true }
        )
        return DefaultScheduledTaskRunExecutor(
            modelContext: fixture.context,
            controllerRegistry: registry,
            notificationManager: makeNotificationManager(fixture: fixture),
            cancellationHandlerAction: { execution in
                execution.cancelProviderTasks()
                joinObserver.recordEntry()
                await execution.cancelConversationActivity()
                joinObserver.recordCompletion()
            }
        )
    }

    private func assertOrdinaryFollowUpRemainsActive(
        _ fixture: ConversationViewModelTestFixture,
        expectedCancelCallCount: Int
    ) async {
        XCTAssertTrue(fixture.viewModel.turnState.isActive)
        let cancelCalls = await fixture.agentsManager.cancelCalls()
        XCTAssertEqual(cancelCalls.count, expectedCancelCallCount)
        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertEqual(spawnCalls.count, 2)
        XCTAssertFalse(spawnCalls[1].config.isAutomatedScheduledTurn)
    }
}

@MainActor
private final class ScheduledExecutionResultBox {
    private var result: Result<ScheduledTaskRunExecutionResult, Error>?

    var hasResolved: Bool {
        result != nil
    }

    func resolve(_ result: Result<ScheduledTaskRunExecutionResult, Error>) {
        self.result = result
    }

    func get() throws -> ScheduledTaskRunExecutionResult {
        guard let result else {
            throw WaitTimeoutError(description: "scheduled execution result was not resolved")
        }
        return try result.get()
    }
}

@MainActor
private final class ScheduledCancellationCleanupGate {
    private(set) var hasEntered = false
    private(set) var hasCompleted = false
    private var isReleased = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func waitForRelease() async {
        hasEntered = true
        guard !isReleased else {
            return
        }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func release() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func recordCompletion() {
        hasCompleted = true
    }
}

@MainActor
private final class ScheduledCancellationJoinObserver {
    private(set) var hasEntered = false
    private(set) var hasCompleted = false
    private var entryContinuation: CheckedContinuation<Void, Never>?

    func recordEntry() {
        hasEntered = true
        entryContinuation?.resume()
        entryContinuation = nil
    }

    func waitUntilEntered() async {
        guard !hasEntered else {
            return
        }
        await withCheckedContinuation { continuation in
            entryContinuation = continuation
        }
    }

    func recordCompletion() {
        hasCompleted = true
    }
}

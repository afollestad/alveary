import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskRunExecutorTests {
    func testPersistedShutdownInterruptionWinsOverLateSuccessfulOutcome() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let run = try attachRun(to: fixture, status: .preparing)
        let notificationManager = ScheduledExecutionNotificationRecorder()
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in },
            suspendRuntime: { _ in },
            runtimeIsSuspended: { _ in true }
        )
        let executor = DefaultScheduledTaskRunExecutor(
            modelContext: fixture.context,
            controllerRegistry: registry,
            notificationManager: notificationManager,
            startAutomatedTurn: { viewModel, _ in
                viewModel.markVisibleTurnStarted()
                viewModel.turnState.beginTurn()
            }
        )
        let execution = Task {
            try await executor.execute(makeMaterialization(run: run, fixture: fixture))
        }
        try await waitUntil("expected scheduled run to start before shutdown") {
            run.status == .running
        }

        try persistShutdownInterruption(run, fixture: fixture)
        let statusExpectation = expectation(description: "scheduled task conversation status published")
        let conversationID = fixture.conversation.id
        let observer = makeStatusObserver(conversationID: conversationID, expectation: statusExpectation)
        defer { NotificationCenter.default.removeObserver(observer) }
        fixture.viewModel.state.endTurn()

        let result = try await execution.value
        await fulfillment(of: [statusExpectation], timeout: 1)
        XCTAssertEqual(result, .interrupted)
        XCTAssertEqual(run.status, .interrupted)
        XCTAssertEqual(run.finishedAt, Date(timeIntervalSinceReferenceDate: 5_000))
        XCTAssertEqual(run.lastError, ScheduledTaskRecoveryInterruptionReason.executionWasInProgress.message)
        XCTAssertTrue(fixture.conversation.isUnread)
        XCTAssertEqual(notificationManager.refreshBadgeCountCalls, 1)
        try assertPersistedInterruption(
            fixture: fixture,
            conversationID: conversationID,
            runID: run.id
        )
    }

    func testTerminalSaveFailureRetainsExecutionUntilRetryIsDurable() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let run = try attachRun(to: fixture, status: .preparing)
        let retryGate = ScheduledPersistenceRetryGate()
        let saver = ScheduledTerminalStateSaver(context: fixture.context, failuresRemaining: 1)
        let suspension = ScheduledExecutionSuspensionRecorder(conversation: fixture.conversation)
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in },
            suspendRuntime: { _ in suspension.recordSuspension() },
            runtimeIsSuspended: { _ in true }
        )
        let executor = DefaultScheduledTaskRunExecutor(
            modelContext: fixture.context,
            controllerRegistry: registry,
            notificationManager: makeNotificationManager(fixture: fixture),
            startAutomatedTurn: { viewModel, _ in
                viewModel.markVisibleTurnStarted()
                viewModel.turnState.beginTurn()
            },
            saveTerminalState: { try saver.save() },
            persistenceRetryWait: { await retryGate.wait() }
        )
        let execution = Task { try await executor.execute(makeMaterialization(run: run, fixture: fixture)) }
        try await waitUntil("expected scheduled run to start") { run.status == .running }

        fixture.project.name = "Unrelated pending project edit"
        fixture.viewModel.state.endTurn()
        try await waitUntil("expected terminal save retry") { retryGate.waitCount == 1 }

        XCTAssertEqual(saver.saveAttempts, 1)
        XCTAssertEqual(run.status, .running)
        XCTAssertFalse(fixture.conversation.isUnread)
        XCTAssertEqual(fixture.project.name, "Unrelated pending project edit")
        XCTAssertIdentical(registry.controller(for: ConversationControllerKey(conversation: fixture.conversation)), fixture.viewModel)
        XCTAssertTrue(suspension.observations.isEmpty)
        XCTAssertTrue(fixture.viewModel.lastTurnError?.contains("Retrying") == true)

        retryGate.open()
        let result = try await execution.value

        XCTAssertEqual(result, .succeeded)
        XCTAssertEqual(saver.saveAttempts, 2)
        XCTAssertEqual(run.status, .success)
        XCTAssertTrue(fixture.conversation.isUnread)
        XCTAssertEqual(fixture.project.name, "Unrelated pending project edit")
        XCTAssertNil(fixture.viewModel.lastTurnError)
        XCTAssertEqual(suspension.observations.count, 1)
        try assertPersistedProjectEdit(fixture: fixture)
    }

    func testTerminalSaveRetryDoesNotRollBackUnrelatedEditCreatedDuringEarlierWait() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let run = try attachRun(to: fixture, status: .preparing)
        let retryGate = ScheduledPersistenceRetryGate()
        let saver = ScheduledTerminalStateSaver(context: fixture.context, failuresRemaining: 2)
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in },
            suspendRuntime: { _ in },
            runtimeIsSuspended: { _ in true }
        )
        let executor = DefaultScheduledTaskRunExecutor(
            modelContext: fixture.context,
            controllerRegistry: registry,
            notificationManager: makeNotificationManager(fixture: fixture),
            startAutomatedTurn: { viewModel, _ in
                viewModel.markVisibleTurnStarted()
                viewModel.turnState.beginTurn()
            },
            saveTerminalState: { try saver.save() },
            persistenceRetryWait: { await retryGate.wait() }
        )
        let execution = Task { try await executor.execute(makeMaterialization(run: run, fixture: fixture)) }
        try await waitUntil("expected scheduled run to start") { run.status == .running }

        fixture.viewModel.state.endTurn()
        try await waitUntil("expected first terminal save retry") { retryGate.waitCount == 1 }
        fixture.project.name = "Edit created during persistence retry"
        retryGate.open()
        try await waitUntil("expected second terminal save retry") { retryGate.waitCount == 2 }

        XCTAssertEqual(fixture.project.name, "Edit created during persistence retry")
        retryGate.open()
        let result = try await execution.value

        XCTAssertEqual(result, .succeeded)
        XCTAssertEqual(saver.saveAttempts, 3)
        XCTAssertEqual(run.status, .success)
        try assertPersistedProjectName(
            "Edit created during persistence retry",
            fixture: fixture
        )
    }

    func testUnmountedQueuedFollowUpStartsAfterAutomatedRuntimeSuspends() async throws {
        let fixture = try makeProjectLocalScheduledTaskFixture()
        let run = try attachRun(to: fixture, status: .preparing, workspaceKind: .project, workspaceStrategy: .localCheckout)
        let suspension = ScheduledExecutionSuspensionRecorder(conversation: fixture.conversation)
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in },
            suspendRuntime: { _ in suspension.recordSuspension() },
            runtimeIsSuspended: { _ in true }
        )
        let executor = DefaultScheduledTaskRunExecutor(
            modelContext: fixture.context,
            controllerRegistry: registry,
            notificationManager: makeNotificationManager(fixture: fixture),
            startAutomatedTurn: { viewModel, _ in
                viewModel.state.liveSessionConfig = try viewModel.makeSpawnConfig(
                    isAutomatedScheduledTurn: true
                )
                viewModel.markVisibleTurnStarted()
                viewModel.turnState.beginTurn()
            }
        )
        let execution = Task { try await executor.execute(makeMaterialization(run: run, fixture: fixture)) }
        defer { execution.cancel() }
        try await waitUntil("expected scheduled run to start") { run.status == .running }
        try await fixture.viewModel.queueOrSend("Continue after the scheduled turn.")
        fixture.viewModel.state.endTurn()
        let result = try await execution.value
        try await waitUntil("expected queued follow-up to start in the background") {
            let spawns = await fixture.agentsManager.spawnCalls()
            let sentMessages = await fixture.agentsManager.sentMessages()
            return spawns.count == 1 && sentMessages == ["Continue after the scheduled turn."]
        }

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        let suspendCalls = await fixture.agentsManager.suspendCalls()
        let destroyCalls = await fixture.agentsManager.destroyCalls()
        let spawn = try XCTUnwrap(spawnCalls.first)
        XCTAssertEqual(result, .succeeded)
        XCTAssertEqual(suspension.observations.count, 1)
        XCTAssertFalse(spawn.config.isAutomatedScheduledTurn)
        XCTAssertFalse(spawn.forkSession)
        XCTAssertEqual(suspendCalls, [fixture.conversation.id])
        XCTAssertTrue(destroyCalls.isEmpty)
        XCTAssertIdentical(
            registry.controller(for: ConversationControllerKey(conversation: fixture.conversation)),
            fixture.viewModel
        )
    }

    func testUnmountedQueuedFollowUpDrainsAfterDeferredFinalizationRetry() async throws {
        let fixture = try makeProjectLocalScheduledTaskFixture()
        let run = try attachRun(to: fixture, status: .preparing, workspaceKind: .project, workspaceStrategy: .localCheckout)
        let retryGate = ScheduledPersistenceRetryGate()
        let flushRecorder = DeferredFinalizationFlushRecorder()
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in try flushRecorder.flush() },
            suspendRuntime: { _ in },
            runtimeIsSuspended: { _ in true }
        )
        let executor = DefaultScheduledTaskRunExecutor(
            modelContext: fixture.context,
            controllerRegistry: registry,
            notificationManager: makeNotificationManager(fixture: fixture),
            startAutomatedTurn: { viewModel, _ in
                viewModel.state.liveSessionConfig = try viewModel.makeSpawnConfig(
                    isAutomatedScheduledTurn: true
                )
                viewModel.markVisibleTurnStarted()
                viewModel.turnState.beginTurn()
            },
            persistenceRetryWait: { await retryGate.wait() }
        )
        let execution = Task { try await executor.execute(makeMaterialization(run: run, fixture: fixture)) }
        defer { execution.cancel() }
        try await waitUntil("expected scheduled run to start") { run.status == .running }
        try await fixture.viewModel.queueOrSend("Continue after finalization retry.")
        fixture.viewModel.state.endTurn()
        try await waitUntil("expected deferred finalization retry") { retryGate.waitCount == 1 }
        let prematureSpawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertEqual(flushRecorder.callCount, 2)
        XCTAssertTrue(fixture.viewModel.lastTurnError?.contains("Retrying") == true)
        XCTAssertNotNil(fixture.viewModel.state.messageQueue.peekNext())
        XCTAssertTrue(prematureSpawnCalls.isEmpty)

        retryGate.open()
        let result = try await execution.value
        try await waitUntil("expected queued follow-up after finalization retry") {
            await fixture.agentsManager.sentMessages() == ["Continue after finalization retry."]
        }

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertEqual(result, .succeeded)
        XCTAssertEqual(flushRecorder.callCount, 3)
        XCTAssertNil(fixture.viewModel.lastTurnError)
        XCTAssertFalse(try XCTUnwrap(spawnCalls.first).config.isAutomatedScheduledTurn)
    }

    func testStopDuringTerminalSaveRetryOverridesSuccessfulOutcome() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let run = try attachRun(to: fixture, status: .preparing)
        let retryGate = ScheduledPersistenceRetryGate()
        let saver = ScheduledTerminalStateSaver(context: fixture.context, failuresRemaining: 1)
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in },
            suspendRuntime: { _ in },
            runtimeIsSuspended: { _ in true }
        )
        let executor = DefaultScheduledTaskRunExecutor(
            modelContext: fixture.context,
            controllerRegistry: registry,
            notificationManager: makeNotificationManager(fixture: fixture),
            startAutomatedTurn: { viewModel, _ in
                viewModel.markVisibleTurnStarted()
                viewModel.turnState.beginTurn()
            },
            saveTerminalState: { try saver.save() },
            persistenceRetryWait: { await retryGate.wait() }
        )
        let execution = Task { try await executor.execute(makeMaterialization(run: run, fixture: fixture)) }
        try await waitUntil("expected scheduled run to start") { run.status == .running }

        fixture.viewModel.state.endTurn()
        try await waitUntil("expected terminal save retry") { retryGate.waitCount == 1 }
        try await executor.stop(runID: run.persistentModelID)
        retryGate.open()

        let result = try await execution.value
        XCTAssertEqual(result, .interrupted)
        XCTAssertEqual(run.status, .interrupted)
        XCTAssertTrue(fixture.conversation.isUnread)
    }

    func testCoordinatorCancellationDuringTerminalSaveRetryPreservesObservedSuccess() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let run = try attachRun(to: fixture, status: .preparing)
        let retryGate = ScheduledPersistenceRetryGate()
        let saver = ScheduledTerminalStateSaver(context: fixture.context, failuresRemaining: 1)
        let suspension = ScheduledExecutionSuspensionRecorder(conversation: fixture.conversation)
        let notifications = ScheduledExecutionNotificationRecorder()
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in },
            suspendRuntime: { _ in suspension.recordSuspension() },
            runtimeIsSuspended: { _ in true }
        )
        let executor = DefaultScheduledTaskRunExecutor(
            modelContext: fixture.context,
            controllerRegistry: registry,
            notificationManager: notifications,
            startAutomatedTurn: { viewModel, _ in
                viewModel.markVisibleTurnStarted()
                viewModel.turnState.beginTurn()
            },
            saveTerminalState: { try saver.save() },
            persistenceRetryWait: { await retryGate.wait() }
        )
        let execution = Task { try await executor.execute(makeMaterialization(run: run, fixture: fixture)) }
        try await waitUntil("expected scheduled run to start") { run.status == .running }

        fixture.viewModel.state.endTurn()
        try await waitUntil("expected terminal save retry") { retryGate.waitCount == 1 }
        execution.cancel()
        retryGate.open()

        let result = try await execution.value
        XCTAssertEqual(result, .succeeded)
        XCTAssertEqual(run.status, .success)
        XCTAssertTrue(fixture.conversation.isUnread)
        XCTAssertEqual(notifications.handledEvents.map(\.event), [.stop(message: nil)])
        XCTAssertEqual(suspension.observations.count, 1)
    }

    func testCoordinatorCancellationDuringTerminalSaveRetryPreservesObservedFailure() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let run = try attachRun(to: fixture, status: .preparing)
        let retryGate = ScheduledPersistenceRetryGate()
        let saver = ScheduledTerminalStateSaver(context: fixture.context, failuresRemaining: 1)
        let suspension = ScheduledExecutionSuspensionRecorder(conversation: fixture.conversation)
        let notifications = ScheduledExecutionNotificationRecorder()
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in },
            suspendRuntime: { _ in suspension.recordSuspension() },
            runtimeIsSuspended: { _ in true }
        )
        let executor = DefaultScheduledTaskRunExecutor(
            modelContext: fixture.context,
            controllerRegistry: registry,
            notificationManager: notifications,
            startAutomatedTurn: { viewModel, _ in
                viewModel.markVisibleTurnStarted()
                viewModel.turnState.beginTurn()
            },
            saveTerminalState: { try saver.save() },
            persistenceRetryWait: { await retryGate.wait() }
        )
        let execution = Task { try await executor.execute(makeMaterialization(run: run, fixture: fixture)) }
        try await waitUntil("expected scheduled run to start") { run.status == .running }

        fixture.viewModel.controllerTerminalFailureMessage = "Provider failed"
        fixture.viewModel.state.endTurn()
        try await waitUntil("expected terminal save retry") { retryGate.waitCount == 1 }
        execution.cancel()
        retryGate.open()

        let result = try await execution.value
        XCTAssertEqual(result, .failed(message: "Provider failed"))
        XCTAssertEqual(run.status, .failure)
        XCTAssertEqual(run.lastError, "Provider failed")
        XCTAssertTrue(fixture.conversation.isUnread)
        guard case .error = notifications.handledEvents.first?.event else {
            return XCTFail("Expected one durable failure notification")
        }
        XCTAssertEqual(notifications.handledEvents.count, 1)
        XCTAssertEqual(suspension.observations.count, 1)
    }
}

private extension ScheduledTaskRunExecutorTests {
    func persistShutdownInterruption(
        _ run: ScheduledTaskRun,
        fixture: ConversationViewModelTestFixture
    ) throws {
        run.status = .interrupted
        run.finishedAt = Date(timeIntervalSinceReferenceDate: 5_000)
        run.lastError = ScheduledTaskRecoveryInterruptionReason.executionWasInProgress.message
        try fixture.context.save()
        XCTAssertFalse(fixture.conversation.isUnread)
    }

    func makeStatusObserver(
        conversationID: String,
        expectation: XCTestExpectation
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .agentStatusChanged,
            object: nil,
            queue: nil
        ) { notification in
            if notification.userInfo?["conversationId"] as? String == conversationID {
                expectation.fulfill()
            }
        }
    }

    func assertPersistedInterruption(
        fixture: ConversationViewModelTestFixture,
        conversationID: String,
        runID: String
    ) throws {
        let context = ModelContext(fixture.container)
        let conversation = try context.fetch(
            FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == conversationID })
        ).first
        let run = try context.fetch(
            FetchDescriptor<ScheduledTaskRun>(predicate: #Predicate { $0.id == runID })
        ).first
        XCTAssertEqual(conversation?.isUnread, true)
        XCTAssertEqual(run?.status, .interrupted)
        XCTAssertEqual(run?.finishedAt, Date(timeIntervalSinceReferenceDate: 5_000))
        XCTAssertEqual(run?.lastError, ScheduledTaskRecoveryInterruptionReason.executionWasInProgress.message)
    }

    func assertPersistedProjectEdit(fixture: ConversationViewModelTestFixture) throws {
        try assertPersistedProjectName("Unrelated pending project edit", fixture: fixture)
    }

    func assertPersistedProjectName(
        _ expectedName: String,
        fixture: ConversationViewModelTestFixture
    ) throws {
        let context = ModelContext(fixture.container)
        let path = fixture.project.path
        let project = try context.fetch(
            FetchDescriptor<Project>(predicate: #Predicate { $0.path == path })
        ).first
        XCTAssertEqual(project?.name, expectedName)
    }
}

@MainActor
private final class ScheduledTerminalStateSaver {
    private let context: ModelContext
    private var failuresRemaining: Int
    private(set) var saveAttempts = 0

    init(context: ModelContext, failuresRemaining: Int) {
        self.context = context
        self.failuresRemaining = failuresRemaining
    }

    func save() throws {
        saveAttempts += 1
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw ScheduledTaskExecutorTestError.saveFailed
        }
        try context.save()
    }
}

@MainActor
private final class ScheduledPersistenceRetryGate {
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
private final class DeferredFinalizationFlushRecorder {
    private(set) var callCount = 0

    func flush() throws {
        callCount += 1
        if callCount == 2 {
            throw ScheduledTaskExecutorTestError.saveFailed
        }
    }
}

@MainActor
final class ScheduledExecutionNotificationRecorder: NotificationManager {
    private(set) var refreshBadgeCountCalls = 0
    private(set) var handledEvents: [(event: ConversationEvent, conversationID: String)] = []
    var onHandleEvent: (@MainActor (ConversationEvent, String) -> Void)?

    func handleEvent(_ event: ConversationEvent, conversationId: String) {
        handledEvents.append((event, conversationId))
        onHandleEvent?(event, conversationId)
    }
    func markConversationRead(conversationId: String) {}
    func handleAppVisibilityChanged() {}
    func refreshBadgeCount() { refreshBadgeCountCalls += 1 }
    func setActiveConversationProvider(_ provider: @escaping @MainActor () -> String?) {}
}

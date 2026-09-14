import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskRunExecutorTests {
    func testExistingTargetHydratedApprovalRejectsExecutionWithoutFinalizingRun() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let baselineModifiedAt = Date(timeIntervalSinceReferenceDate: 6_000)
        let run = try makeExistingTargetRun(fixture: fixture, modifiedAt: baselineModifiedAt)
        let approvalRecord = try insertUnresolvedApproval(into: fixture)

        let suspension = ScheduledExecutionSuspensionRecorder(
            conversation: fixture.conversation,
            run: run
        )
        let notifications = ScheduledExecutionNotificationRecorder()
        var startAutomatedTurnCalls = 0
        var executionSaveCalls = 0
        var terminalSaveCalls = 0
        var finalizationSaveCalls = 0
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
            startAutomatedTurn: { _, _ in startAutomatedTurnCalls += 1 },
            saveExecutionState: { executionSaveCalls += 1 },
            saveTerminalState: { terminalSaveCalls += 1 },
            saveFinalizationState: { finalizationSaveCalls += 1 }
        )

        do {
            _ = try await executor.execute(makeMaterialization(run: run, fixture: fixture))
            XCTFail("Expected the hydrated approval to keep the existing target busy")
        } catch {
            XCTAssertEqual(error as? ScheduledTaskRunExecutionError, .existingTargetBusy)
        }

        XCTAssertEqual(startAutomatedTurnCalls, 0)
        XCTAssertEqual(executionSaveCalls, 0)
        XCTAssertEqual(terminalSaveCalls, 0)
        XCTAssertEqual(finalizationSaveCalls, 0)
        XCTAssertEqual(run.status, .preparing)
        XCTAssertNil(run.startedAt)
        XCTAssertNil(run.finishedAt)
        XCTAssertNil(run.lastError)
        XCTAssertEqual(fixture.thread.modifiedAt, baselineModifiedAt)
        XCTAssertFalse(fixture.conversation.isUnread)
        XCTAssertNil(approvalRecord.toolApprovalStatus)
        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.request.toolUseId, "approval-1")
        XCTAssertTrue(notifications.handledEvents.isEmpty)
        XCTAssertTrue(suspension.observations.isEmpty)
    }

    func testExistingTargetTerminalSaveFailureRestoresModifiedDateBeforeRetryPreflush() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let baselineModifiedAt = Date(timeIntervalSinceReferenceDate: 7_000)
        let terminalDate = Date(timeIntervalSinceReferenceDate: 8_000)
        let run = try makeExistingTargetRun(fixture: fixture, modifiedAt: baselineModifiedAt)
        let retryGate = ExistingTargetPersistenceRetryGate()
        var saveAttempts = 0
        var persistedModifiedAtBeforeRetrySave: Date?
        let targetThreadID = fixture.thread.persistentModelID
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
            saveTerminalState: {
                saveAttempts += 1
                if saveAttempts == 1 {
                    throw ScheduledTaskExecutorTestError.saveFailed
                }
                let verificationContext = ModelContext(fixture.container)
                persistedModifiedAtBeforeRetrySave = verificationContext.resolveThread(id: targetThreadID)?.modifiedAt
                try fixture.context.save()
            },
            persistenceRetryWait: { await retryGate.wait() },
            now: { terminalDate }
        )
        let execution = Task {
            try await executor.execute(makeMaterialization(run: run, fixture: fixture))
        }
        try await waitUntil("expected attached scheduled run to start") { run.status == .running }

        fixture.viewModel.state.endTurn()
        try await waitUntil("expected attached terminal save retry") { retryGate.waitCount == 1 }

        XCTAssertEqual(saveAttempts, 1)
        XCTAssertEqual(fixture.thread.modifiedAt, baselineModifiedAt)

        retryGate.open()
        let result = try await execution.value

        XCTAssertEqual(result, .succeeded)
        XCTAssertEqual(persistedModifiedAtBeforeRetrySave, baselineModifiedAt)
        XCTAssertEqual(fixture.thread.modifiedAt, terminalDate)
    }

    func testExistingTargetResolvedApprovalFinishesRecoveryBeforeStartingRun() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let run = try makeExistingTargetRun(fixture: fixture, modifiedAt: Date())
        let approvalRecord = try insertUnresolvedApproval(into: fixture)
        let recoveryGate = ExistingTargetPersistenceRetryGate()
        fixture.viewModel.readToolApprovalTranscript = { _ in
            await recoveryGate.wait()
            return .approved
        }
        var startCalls = 0
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in },
            suspendRuntime: { _ in },
            runtimeIsSuspended: { _ in true }
        )
        let executor = DefaultScheduledTaskRunExecutor(
            modelContext: fixture.context,
            controllerRegistry: registry,
            notificationManager: ScheduledExecutionNotificationRecorder(),
            startAutomatedTurn: { viewModel, _ in
                startCalls += 1
                viewModel.markVisibleTurnStarted()
                viewModel.turnState.beginTurn()
            }
        )
        let execution = Task { try await executor.execute(makeMaterialization(run: run, fixture: fixture)) }
        try await waitUntil("expected scheduled approval recovery") { recoveryGate.waitCount == 1 }

        XCTAssertTrue(fixture.viewModel.state.isRestoringToolApproval)
        XCTAssertFalse(fixture.viewModel.isReadyForExistingScheduledTask)
        XCTAssertEqual(startCalls, 0)
        XCTAssertEqual(run.status, .preparing)
        XCTAssertNil(run.startedAt)

        recoveryGate.open()
        try await waitUntil("expected resolved approval to allow scheduled execution") { run.status == .running }
        XCTAssertEqual(approvalRecord.toolApprovalStatus, ToolApprovalStatus.approved.rawValue)
        fixture.viewModel.state.endTurn()
        let result = try await execution.value

        XCTAssertEqual(result, .succeeded)
        XCTAssertEqual(startCalls, 1)
    }

    func testExistingTargetRecoveryRevalidatesCancellationStopAndRunState() async throws {
        for interruption in ApprovalRecoveryInterruption.allCases {
            let fixture = try ConversationViewModelTestFixture()
            let run = try makeExistingTargetRun(fixture: fixture, modifiedAt: Date())
            _ = try insertUnresolvedApproval(into: fixture)
            let recoveryGate = ExistingTargetPersistenceRetryGate()
            fixture.viewModel.readToolApprovalTranscript = { _ in
                await recoveryGate.wait()
                return .approved
            }
            var startCalls = 0
            let registry = DefaultConversationControllerRegistry(
                makeViewModel: { _ in fixture.viewModel },
                flushTerminalRecords: { _ in },
                suspendRuntime: { _ in },
                runtimeIsSuspended: { _ in true }
            )
            let executor = DefaultScheduledTaskRunExecutor(
                modelContext: fixture.context,
                controllerRegistry: registry,
                notificationManager: ScheduledExecutionNotificationRecorder(),
                startAutomatedTurn: { _, _ in startCalls += 1 }
            )
            let materialization = makeMaterialization(run: run, fixture: fixture)
            let execution = Task { try await executor.execute(materialization) }
            try await waitUntil("expected scheduled approval recovery") { recoveryGate.waitCount == 1 }
            switch interruption {
            case .cancellation: execution.cancel()
            case .stop: try await executor.stop(runID: run.persistentModelID)
            case .changedRun:
                run.status = .interrupted
                try fixture.context.save()
            }
            recoveryGate.open()
            do {
                _ = try await execution.value
                XCTFail("Expected stale scheduled preparation to be rejected")
            } catch {
                if interruption == .changedRun {
                    XCTAssertEqual(error as? ScheduledTaskRunExecutionError, .invalidRunStatus(.interrupted))
                } else {
                    XCTAssertTrue(error is CancellationError)
                }
            }
            XCTAssertEqual(startCalls, 0)
            XCTAssertNil(run.startedAt)
            XCTAssertNil(run.finishedAt)
            XCTAssertFalse(fixture.viewModel.state.isAutomatedScheduledRunActive)
            XCTAssertNil(registry.controller(for: ConversationControllerKey(conversationID: fixture.conversation.id)))
        }
    }
}

private enum ApprovalRecoveryInterruption: CaseIterable {
    case cancellation, stop, changedRun
}

@MainActor
private extension ScheduledTaskRunExecutorTests {
    func insertUnresolvedApproval(
        into fixture: ConversationViewModelTestFixture
    ) throws -> ConversationEventRecord {
        let record = ConversationEventRecord(
            conversationId: fixture.conversation.id,
            type: "tool_approval",
            content: "session-1",
            toolId: "approval-1",
            toolName: "Bash",
            toolInput: "{}",
            conversation: fixture.conversation
        )
        fixture.context.insert(record)
        try fixture.context.save()
        return record
    }

    func makeExistingTargetRun(
        fixture: ConversationViewModelTestFixture,
        modifiedAt: Date
    ) throws -> ScheduledTaskRun {
        fixture.thread.isPinned = true
        fixture.thread.modifiedAt = modifiedAt
        let run = try attachRun(to: fixture, status: .preparing)
        fixture.thread.scheduledTaskRun = nil
        run.thread = nil
        run.destinationSnapshot = .existingThread
        run.targetConversationIDSnapshot = fixture.conversation.id
        run.targetThread = fixture.thread
        try fixture.context.save()
        return run
    }
}

@MainActor
private final class ExistingTargetPersistenceRetryGate {
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

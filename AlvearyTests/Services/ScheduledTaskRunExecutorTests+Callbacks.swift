import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskRunExecutorTests {
    func testExecutionTracksWaitingThenFinishesUnreadAndAwaitsRuntimeSuspension() async throws {
        for secondaryCallback in [false, true] {
            try await assertWaitingExecution(secondaryCallback: secondaryCallback)
        }
    }

    private func assertWaitingExecution(secondaryCallback: Bool) async throws {
        let (fixture, run) = try makeExecutionTarget(secondaryCallback: secondaryCallback)
        let suspension = ScheduledExecutionSuspensionRecorder(conversation: fixture.conversation)
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in },
            suspendRuntime: { _ in suspension.recordSuspension() }, runtimeIsSuspended: { _ in true }
        )
        let notificationManager = ScheduledExecutionNotificationRecorder()
        var notifiedRunStatus: ScheduledTaskRunStatus?
        var notificationConversationWasUnread = false
        var suspensionCountAtNotification = 0
        notificationManager.onHandleEvent = { _, _ in
            notifiedRunStatus = run.status
            notificationConversationWasUnread = fixture.conversation.isUnread
            suspensionCountAtNotification = suspension.observations.count
        }
        let executor = DefaultScheduledTaskRunExecutor(
            modelContext: fixture.context,
            controllerRegistry: registry,
            notificationManager: notificationManager,
            startAutomatedTurn: { viewModel, _ in
                viewModel.markVisibleTurnStarted()
                viewModel.turnState.beginTurn()
            },
            now: { Date(timeIntervalSinceReferenceDate: 1_000) }
        )
        let materialization = makeMaterialization(run: run, fixture: fixture)

        let execution = Task { try await executor.execute(materialization) }
        try await waitUntil("expected scheduled run to start") { run.status == .running }

        let approval = makeToolApproval()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
        try await waitUntil("expected scheduled run to wait") {
            run.status == .waiting
        }

        fixture.viewModel.state.pendingToolApproval = nil
        fixture.viewModel.state.endTurn()
        let result = try await execution.value

        XCTAssertEqual(result, .succeeded)
        XCTAssertEqual(run.status, .success)
        assertTerminalActivity(run: run, thread: fixture.thread, at: Date(timeIntervalSinceReferenceDate: 1_000))
        XCTAssertTrue(fixture.conversation.isUnread)
        XCTAssertFalse(fixture.thread.conversations.filter { $0.id != fixture.conversation.id }.contains(where: \.isUnread))
        XCTAssertEqual(notificationManager.handledEvents.map(\.conversationID), [fixture.conversation.id])
        XCTAssertEqual(suspension.observations.count, 1)
        XCTAssertEqual(suspension.observations.first?.conversationWasUnread, true)
        XCTAssertEqual(notificationManager.handledEvents.map(\.event), [.stop(message: nil)])
        XCTAssertEqual(notifiedRunStatus, .success)
        XCTAssertTrue(notificationConversationWasUnread)
        XCTAssertEqual(suspensionCountAtNotification, 1)
    }

    private func makeExecutionTarget(secondaryCallback: Bool) throws -> (ConversationViewModelTestFixture, ScheduledTaskRun) {
        let fixture = try ConversationViewModelTestFixture()
        let run = try attachRun(to: fixture, status: .preparing)
        if secondaryCallback {
            fixture.conversation.isMain = false
            fixture.context.insert(Conversation(harness: "claude", isMain: true, thread: fixture.thread))
            fixture.thread.scheduledTaskRun = nil
            run.thread = nil
            run.targetThread = fixture.thread
            run.destinationSnapshot = .existingThread
            run.targetConversationIDSnapshot = fixture.conversation.id
            run.isExactTargetSnapshot = true
            try fixture.context.save()
        }
        return (fixture, run)
    }
}

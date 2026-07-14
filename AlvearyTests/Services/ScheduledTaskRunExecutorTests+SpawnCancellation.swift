import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskRunExecutorTests {
    func testStopDuringProviderSpawnDestroysLateCancelledLaunch() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        let run = try XCTUnwrap(fixture.thread.scheduledTaskRun)
        await fixture.agentsManager.failDestroyWhenCurrentTaskIsCancelled()
        await fixture.agentsManager.pauseNextSpawn()
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in },
            suspendRuntime: { _ in },
            runtimeIsSuspended: { _ in true }
        )
        let executor = DefaultScheduledTaskRunExecutor(
            modelContext: fixture.context,
            controllerRegistry: registry,
            notificationManager: makeNotificationManager(fixture: fixture)
        )
        let execution = Task {
            try await executor.execute(spawnCancellationMaterialization(run: run, fixture: scheduledFixture))
        }
        await fixture.agentsManager.waitUntilSpawnEntered()

        let stop = Task { @MainActor in
            try await executor.stop(runID: run.persistentModelID)
        }
        await fixture.agentsManager.waitUntilSpawnCancellationObserved()
        await fixture.agentsManager.resumePausedSpawn()
        try await stop.value
        let result = try await execution.value

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        let destroyCalls = await fixture.agentsManager.destroyCalls()
        let sentMessages = await fixture.agentsManager.sentMessages()
        let runtimeIsRunning = await fixture.agentsManager.isRunning(conversationId: fixture.conversation.id)
        XCTAssertEqual(result, .interrupted)
        XCTAssertEqual(run.status, .interrupted)
        XCTAssertEqual(spawnCalls.count, 1)
        XCTAssertEqual(destroyCalls, [fixture.conversation.id])
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertTrue(try fixture.userMessages().isEmpty)
        XCTAssertFalse(try fixture.dbThread().hasCompletedInitialSetup)
        XCTAssertFalse(runtimeIsRunning)
    }

    private func spawnCancellationMaterialization(
        run: ScheduledTaskRun,
        fixture scheduledFixture: ScheduledConversationViewModelFixture
    ) throws -> ScheduledTaskRunMaterialization {
        let fixture = scheduledFixture.fixture
        return ScheduledTaskRunMaterialization(
            runID: run.persistentModelID,
            threadID: fixture.thread.persistentModelID,
            conversationID: fixture.conversation.id,
            prompt: run.promptSnapshot,
            workspace: try XCTUnwrap(fixture.thread.taskWorkspaceDescriptor)
        )
    }
}

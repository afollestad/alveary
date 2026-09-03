import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskRunExecutorTests {
    func testEveryScheduledTurnOpensWithThePreamble() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let run = try attachRun(to: fixture, status: .preparing)
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in },
            suspendRuntime: { _ in },
            runtimeIsSuspended: { _ in true }
        )
        var sentPrompt: String?
        let executor = DefaultScheduledTaskRunExecutor(
            modelContext: fixture.context,
            controllerRegistry: registry,
            notificationManager: ScheduledExecutionNotificationRecorder(),
            startAutomatedTurn: { viewModel, prompt in
                sentPrompt = prompt
                viewModel.markVisibleTurnStarted()
                viewModel.turnState.beginTurn()
            },
            now: { Date(timeIntervalSinceReferenceDate: 1_000) }
        )

        let execution = Task { try await executor.execute(makeMaterialization(run: run, fixture: fixture)) }
        try await waitUntil("expected scheduled run to start") {
            run.status == .running
        }
        fixture.viewModel.state.endTurn()
        _ = try await execution.value

        XCTAssertEqual(sentPrompt, "This is a scheduled task run.\n\nRun scheduled work.")
        XCTAssertEqual(run.promptSnapshot, "Run scheduled work.")
    }
}

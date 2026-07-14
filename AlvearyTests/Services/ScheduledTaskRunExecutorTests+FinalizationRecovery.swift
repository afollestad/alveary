import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskRunExecutorTests {
    // swiftlint:disable:next function_body_length
    func testFinalizationSupersedesEveryLateQuestionBeforeClearingRecoveryMarker() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let run = try attachRun(to: fixture, status: .preparing)
        let questionIDs = ["late-question-1", "late-question-2"]
        let promptInput = #"{"questions":[{"question":"Continue?","options":[{"label":"Yes","description":"Continue"}]}]}"#
        var suspensionCount = 0
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            suspendRuntime: { viewModel in
                suspensionCount += 1
                guard suspensionCount == 1 else {
                    return
                }
                for questionID in questionIDs {
                    viewModel.handleEvent(.toolCall(
                        id: questionID,
                        name: "AskUserQuestion",
                        input: promptInput,
                        parentToolUseId: nil,
                        callerAgent: nil
                    ))
                }
            },
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
            persistenceRetryWait: { await Task.yield() }
        )
        let execution = Task {
            try await executor.execute(makeMaterialization(run: run, fixture: fixture))
        }
        try await waitUntil("expected scheduled run to start") {
            run.status == .running
        }

        fixture.viewModel.state.endTurn()
        let result = try await execution.value

        let verificationContext = ModelContext(fixture.container)
        let persistedRun = try XCTUnwrap(
            verificationContext.resolveScheduledTaskRun(id: run.persistentModelID)
        )
        let persistedQuestions = try verificationContext.fetch(
            FetchDescriptor<ConversationEventRecord>()
        ).filter {
            $0.conversationId == fixture.conversation.id &&
                $0.type == "tool_call" &&
                questionIDs.contains($0.toolId ?? "")
        }
        XCTAssertEqual(result, .succeeded)
        XCTAssertEqual(suspensionCount, 2)
        XCTAssertEqual(Set(persistedQuestions.compactMap(\.toolId)), Set(questionIDs))
        XCTAssertTrue(persistedQuestions.allSatisfy {
            $0.content == ChatItemGrouper.handledPromptSummary
        })
        XCTAssertFalse(persistedRun.requiresFinalizationRecovery)
    }

    func testFinalizationMarkerSaveRetriesBeforeRunWideFenceReleases() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let run = try attachRun(to: fixture, status: .preparing)
        let retryGate = ScheduledFinalizationMarkerRetryGate()
        var finalizationSaveAttempts = 0
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
            saveFinalizationState: {
                finalizationSaveAttempts += 1
                if finalizationSaveAttempts == 1 {
                    throw ScheduledTaskExecutorTestError.saveFailed
                }
                try fixture.context.save()
            },
            persistenceRetryWait: { await retryGate.wait() }
        )
        let execution = Task {
            try await executor.execute(makeMaterialization(run: run, fixture: fixture))
        }
        try await waitUntil("expected scheduled run to start") {
            run.status == .running
        }

        fixture.viewModel.state.endTurn()
        await retryGate.waitUntilEntered()

        XCTAssertEqual(run.status, .success)
        XCTAssertTrue(run.requiresFinalizationRecovery)
        XCTAssertTrue(fixture.viewModel.state.isAutomatedScheduledRunActive)
        XCTAssertTrue(fixture.runtimeStore.isAutomatedScheduledRunActive(runID: run.id))

        retryGate.release()
        let result = try await execution.value

        XCTAssertEqual(result, .succeeded)
        XCTAssertEqual(finalizationSaveAttempts, 2)
        XCTAssertFalse(run.requiresFinalizationRecovery)
        XCTAssertFalse(fixture.viewModel.state.isAutomatedScheduledRunActive)
        XCTAssertFalse(fixture.runtimeStore.isAutomatedScheduledRunActive(runID: run.id))
    }
}

@MainActor
private final class ScheduledFinalizationMarkerRetryGate {
    private var didEnter = false
    private var entryContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func wait() async {
        didEnter = true
        entryContinuation?.resume()
        entryContinuation = nil
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilEntered() async {
        guard !didEnter else {
            return
        }
        await withCheckedContinuation { continuation in
            entryContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

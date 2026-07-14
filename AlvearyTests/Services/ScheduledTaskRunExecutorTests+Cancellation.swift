import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskRunExecutorTests {
    func testStopDuringProviderSetupPreventsScheduledRuntimeLaunch() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        let run = try XCTUnwrap(fixture.thread.scheduledTaskRun)
        let gate = ScheduledProviderStartGate()
        await fixture.providerSetup.setPrepareForSpawnHook {
            await gate.waitForRelease()
        }
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
            try await executor.execute(makeScheduledMaterialization(run: run, scheduledFixture: scheduledFixture))
        }
        await gate.waitUntilEntered()

        let stop = Task { @MainActor in
            try await executor.stop(runID: run.persistentModelID)
        }
        await gate.waitUntilCancellationObserved()
        await gate.release()
        try await stop.value
        let result = try await execution.value
        let spawnCalls = await fixture.agentsManager.spawnCalls()
        let sentMessages = await fixture.agentsManager.sentMessages()

        XCTAssertEqual(result, .interrupted)
        XCTAssertEqual(run.status, .interrupted)
        XCTAssertTrue(spawnCalls.isEmpty)
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertTrue(try fixture.userMessages().isEmpty)
    }

    func testCoordinatorCancellationDuringProviderSetupPreventsScheduledRuntimeLaunch() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        let run = try XCTUnwrap(fixture.thread.scheduledTaskRun)
        let gate = ScheduledProviderStartGate()
        await fixture.providerSetup.setPrepareForSpawnHook {
            await gate.waitForRelease()
        }
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
            try await executor.execute(makeScheduledMaterialization(run: run, scheduledFixture: scheduledFixture))
        }
        await gate.waitUntilEntered()

        execution.cancel()
        await gate.waitUntilCancellationObserved()
        await gate.release()
        let result = try await execution.value
        let spawnCalls = await fixture.agentsManager.spawnCalls()
        let sentMessages = await fixture.agentsManager.sentMessages()

        XCTAssertEqual(result, .interrupted)
        XCTAssertEqual(run.status, .interrupted)
        XCTAssertTrue(spawnCalls.isEmpty)
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertTrue(try fixture.userMessages().isEmpty)
    }

    func testTranscriptStopDuringProviderSetupClearsPendingAndInterruptsWithoutLaunching() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        let run = try XCTUnwrap(fixture.thread.scheduledTaskRun)
        let pendingOccurrenceAt = Date(timeIntervalSinceReferenceDate: 12_000)
        let definition = try attachDefinition(
            to: run,
            pendingOccurrenceAt: pendingOccurrenceAt,
            fixture: fixture
        )

        let gate = ScheduledProviderStartGate()
        await fixture.providerSetup.setPrepareForSpawnHook {
            await gate.waitForRelease()
        }
        let coordinator = try makeCoordinator(scheduledFixture: scheduledFixture, run: run)

        XCTAssertEqual(coordinator.resumeClaimedRuns([run.persistentModelID]), 1)
        await gate.waitUntilEntered()

        let stop = Task { @MainActor in
            await fixture.viewModel.cancel()
        }
        await gate.waitUntilCancellationObserved()
        await gate.release()
        await stop.value
        await coordinator.waitUntilIdle()

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(spawnCalls.isEmpty)
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertTrue(try fixture.userMessages().isEmpty)
        XCTAssertEqual(run.status, .interrupted)
        XCTAssertNil(definition.pendingOccurrenceAt)
        XCTAssertTrue(coordinator.activeRunIDs.isEmpty)
    }

    func testStopAndWaitSupersedesInactiveDeferredQuestionAndClearsPendingOccurrence() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        let run = try XCTUnwrap(fixture.thread.scheduledTaskRun)
        let definition = try attachDefinition(
            to: run,
            pendingOccurrenceAt: Date(timeIntervalSinceReferenceDate: 12_500),
            fixture: fixture
        )
        let coordinator = try makeCoordinator(scheduledFixture: scheduledFixture, run: run)

        XCTAssertEqual(coordinator.resumeClaimedRuns([run.persistentModelID]), 1)
        let approval = try await enterInactiveDeferredQuestion(run: run, fixture: fixture)

        try await coordinator.stopAndWait(runID: run.persistentModelID)

        let approvalRecord = try XCTUnwrap(fixture.records(type: "tool_approval").first)
        let promptRecord = try XCTUnwrap(fixture.records(type: "tool_call").first {
            $0.toolId == approval.toolUseId
        })
        XCTAssertEqual(run.status, .interrupted)
        XCTAssertNil(definition.pendingOccurrenceAt)
        XCTAssertEqual(approvalRecord.toolApprovalStatus, ToolApprovalStatus.superseded.rawValue)
        XCTAssertEqual(promptRecord.content, ChatItemGrouper.handledPromptSummary)
        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertNil(fixture.viewModel.state.grouper.latestUnansweredPrompt)
        XCTAssertFalse(fixture.viewModel.state.hasDeferredControllerTerminalBoundary)
        XCTAssertTrue(try fixture.records(type: "stop").contains {
            $0.content == ConversationInterruption.displayMessage
        })
        XCTAssertFalse(coordinator.isActive(runID: run.persistentModelID))
        XCTAssertTrue(coordinator.activeRunIDs.isEmpty)
    }

    func testStopAndWaitSupersedesLiveApprovalAndSuspendsRuntime() async throws {
        try await assertStopAndWaitSupersedesLiveInteraction(.approval)
    }

    func testStopAndWaitSupersedesLiveQuestionAndSuspendsRuntime() async throws {
        try await assertStopAndWaitSupersedesLiveInteraction(.question)
    }
}

@MainActor
private extension ScheduledTaskRunExecutorTests {
    func makeScheduledMaterialization(
        run: ScheduledTaskRun,
        scheduledFixture: ScheduledConversationViewModelFixture
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

    func attachDefinition(
        to run: ScheduledTaskRun,
        pendingOccurrenceAt: Date,
        fixture: ConversationViewModelTestFixture
    ) throws -> ScheduledTask {
        let definition = ScheduledTask(
            id: run.definitionID,
            title: run.titleSnapshot,
            prompt: run.promptSnapshot,
            recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: run.timeZoneIdentifierSnapshot,
            providerID: run.providerIDSnapshot,
            effort: run.effortSnapshot,
            permissionMode: run.permissionModeSnapshot,
            workspaceKind: .project,
            workspaceStrategy: .localCheckout,
            pendingOccurrenceAt: pendingOccurrenceAt,
            runs: [run]
        )
        run.scheduledTask = definition
        run.status = .claimed
        fixture.context.insert(definition)
        try fixture.context.save()
        return definition
    }

    func makeCoordinator(
        scheduledFixture: ScheduledConversationViewModelFixture,
        run: ScheduledTaskRun,
        suspensionRecorder: ScheduledExecutionSuspensionRecorder? = nil
    ) throws -> ScheduledTaskSchedulerCoordinator {
        let fixture = scheduledFixture.fixture
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in },
            suspendRuntime: { viewModel in
                guard let suspensionRecorder else {
                    return
                }
                let conversationID = viewModel.conversation.id
                await viewModel.agentsManager.suspendRuntime(conversationId: conversationID)
                suspensionRecorder.recordSuspension()
            },
            runtimeIsSuspended: { viewModel in
                guard suspensionRecorder != nil else {
                    return true
                }
                let conversationID = viewModel.conversation.id
                return await viewModel.agentsManager.isRuntimeSuspended(
                    conversationId: conversationID
                )
            }
        )
        let notificationManager = makeNotificationManager(fixture: fixture)
        let executor = DefaultScheduledTaskRunExecutor(
            modelContext: fixture.context,
            controllerRegistry: registry,
            notificationManager: notificationManager
        )
        return ScheduledTaskSchedulerCoordinator(
            modelContext: fixture.context,
            engine: ScheduledTaskSchedulerEngine(
                modelContext: fixture.context,
                preflightValidator: { snapshot in scheduledTaskReadyOutcome(for: snapshot) }
            ),
            rootLock: ScheduledTaskRootLock(),
            materializer: ExistingRunMaterializer(
                modelContext: fixture.context,
                materialization: try makeScheduledMaterialization(run: run, scheduledFixture: scheduledFixture)
            ),
            executor: executor,
            keepAwakeService: fixture.keepAwakeService,
            notificationManager: notificationManager
        )
    }

    func assertStopAndWaitSupersedesLiveInteraction(
        _ interaction: ScheduledLiveInteraction
    ) async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        let run = try XCTUnwrap(fixture.thread.scheduledTaskRun)
        let definition = try attachDefinition(
            to: run,
            pendingOccurrenceAt: Date(timeIntervalSinceReferenceDate: 12_750),
            fixture: fixture
        )
        let suspensionRecorder = ScheduledExecutionSuspensionRecorder(
            conversation: fixture.conversation,
            run: run
        )
        let coordinator = try makeCoordinator(
            scheduledFixture: scheduledFixture,
            run: run,
            suspensionRecorder: suspensionRecorder
        )

        XCTAssertEqual(coordinator.resumeClaimedRuns([run.persistentModelID]), 1)
        let approval = try await enterLiveInteraction(
            interaction,
            run: run,
            fixture: fixture
        )

        let stop = Task { @MainActor in
            try await coordinator.stopAndWait(runID: run.persistentModelID)
        }
        try await waitUntil("expected live scheduled interaction cancellation") {
            await fixture.agentsManager.cancelCalls().isEmpty == false
        }
        fixture.viewModel.state.lastTurnInterrupted = true
        fixture.viewModel.state.endTurn()
        try await stop.value

        XCTAssertEqual(run.status, .interrupted)
        XCTAssertNil(definition.pendingOccurrenceAt)
        try assertLiveInteractionWasSuperseded(interaction, approval: approval, fixture: fixture)
        XCTAssertEqual(suspensionRecorder.observations.count, 1)
        XCTAssertFalse(coordinator.isActive(runID: run.persistentModelID))
        XCTAssertTrue(coordinator.activeRunIDs.isEmpty)
        let suspendCalls = await fixture.agentsManager.suspendCalls()
        XCTAssertEqual(suspendCalls, [fixture.conversation.id])
    }

    func enterLiveInteraction(
        _ interaction: ScheduledLiveInteraction,
        run: ScheduledTaskRun,
        fixture: ConversationViewModelTestFixture
    ) async throws -> ToolApprovalRequest {
        try await waitUntil("expected automated scheduled turn to start") {
            run.status == .running && fixture.viewModel.turnState.isActive
        }
        let approval = interaction.approval
        if interaction == .question {
            fixture.viewModel.handleEvent(.toolCall(
                id: approval.toolUseId,
                name: approval.toolName,
                input: approval.toolInput,
                parentToolUseId: nil,
                callerAgent: nil
            ))
        }
        fixture.viewModel.handleEvent(.toolApprovalRequested(approval))
        try await waitUntil("expected scheduled run to wait on a live interaction") {
            run.status == .waiting
        }
        return approval
    }

    func assertLiveInteractionWasSuperseded(
        _ interaction: ScheduledLiveInteraction,
        approval: ToolApprovalRequest,
        fixture: ConversationViewModelTestFixture
    ) throws {
        let approvalRecord = try XCTUnwrap(fixture.records(type: "tool_approval").first {
            $0.toolId == approval.toolUseId
        })
        XCTAssertEqual(approvalRecord.toolApprovalStatus, ToolApprovalStatus.superseded.rawValue)
        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertNil(fixture.viewModel.state.grouper.latestUnansweredPrompt)
        if interaction == .question {
            let promptRecord = try XCTUnwrap(fixture.records(type: "tool_call").first {
                $0.toolId == approval.toolUseId
            })
            XCTAssertEqual(promptRecord.content, ChatItemGrouper.handledPromptSummary)
        }
    }

    func enterInactiveDeferredQuestion(
        run: ScheduledTaskRun,
        fixture: ConversationViewModelTestFixture
    ) async throws -> ToolApprovalRequest {
        try await waitUntil("expected automated scheduled turn to start") {
            run.status == .running && fixture.viewModel.turnState.isActive
        }
        let promptInput = #"{"questions":[{"question":"Continue?","options":[{"label":"Yes","description":"Continue"}]}]}"#
        let approval = ToolApprovalRequest(
            sessionId: "scheduled-session",
            toolUseId: "scheduled-question",
            toolName: "AskUserQuestion",
            toolInput: promptInput
        )
        fixture.viewModel.handleEvent(.toolCall(
            id: approval.toolUseId,
            name: approval.toolName,
            input: promptInput,
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
        try await waitUntil("expected scheduled run to wait on deferred question") {
            run.status == .waiting
        }
        return approval
    }
}

private enum ScheduledLiveInteraction: Equatable {
    case approval
    case question

    var approval: ToolApprovalRequest {
        switch self {
        case .approval:
            ToolApprovalRequest(
                sessionId: "scheduled-session",
                toolUseId: "scheduled-approval",
                toolName: "Bash",
                toolInput: #"{"command":"swift test"}"#
            )
        case .question:
            ToolApprovalRequest(
                sessionId: "scheduled-session",
                toolUseId: "scheduled-question",
                toolName: "AskUserQuestion",
                toolInput: #"{"questions":[{"question":"Continue?","options":[{"label":"Yes","description":"Continue"}]}]}"#
            )
        }
    }
}

private actor ScheduledProviderStartGate {
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
private final class ExistingRunMaterializer: ScheduledTaskRunMaterializing {
    private let modelContext: ModelContext
    private let materialization: ScheduledTaskRunMaterialization

    init(
        modelContext: ModelContext,
        materialization: ScheduledTaskRunMaterialization
    ) {
        self.modelContext = modelContext
        self.materialization = materialization
    }

    func materialize(runID: PersistentIdentifier) async throws -> ScheduledTaskRunMaterialization {
        guard runID == materialization.runID,
              let run = modelContext.resolveScheduledTaskRun(id: runID),
              run.status == .claimed else {
            throw ScheduledTaskRunMaterializationError.runChangedDuringPreparation
        }
        run.status = .preparing
        run.preparationStartedAt = .now
        try modelContext.save()
        return materialization
    }
}

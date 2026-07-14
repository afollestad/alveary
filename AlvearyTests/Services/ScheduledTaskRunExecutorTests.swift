import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ScheduledTaskRunExecutorTests: XCTestCase {
    func testExecutionTracksWaitingThenFinishesUnreadAndAwaitsRuntimeSuspension() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let run = try attachRun(to: fixture, status: .preparing)
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
        try await waitUntil("expected scheduled run to start") {
            run.status == .running
        }

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
        XCTAssertEqual(suspension.observations.count, 1)
        XCTAssertEqual(suspension.observations.first?.conversationWasUnread, true)
        XCTAssertEqual(notificationManager.handledEvents.map(\.event), [.stop(message: nil)])
        XCTAssertEqual(notifiedRunStatus, .success)
        XCTAssertTrue(notificationConversationWasUnread)
        XCTAssertEqual(suspensionCountAtNotification, 1)
    }

    func testTerminalFinalizationRepairsUnknownPersistedRunStatus() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let run = try attachRun(to: fixture, status: .preparing)
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
        run.statusRawValue = "future-status"
        try fixture.context.save()

        fixture.viewModel.state.endTurn()
        let result = try await execution.value

        XCTAssertEqual(result, .succeeded)
        XCTAssertEqual(run.status, .success)
        XCTAssertTrue(run.hasKnownTerminalStatus)
    }

    func testLaunchFailureCreatesTerminalAttemptAndFinalizesRuntime() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let run = try attachRun(to: fixture, status: .preparing)
        let suspension = ScheduledExecutionSuspensionRecorder(conversation: fixture.conversation)
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in },
            suspendRuntime: { _ in suspension.recordSuspension() },
            runtimeIsSuspended: { _ in true }
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
            startAutomatedTurn: { _, _ in throw ScheduledTaskExecutorTestError.launchFailed },
            now: { Date(timeIntervalSinceReferenceDate: 2_000) }
        )

        let result = try await executor.execute(makeMaterialization(run: run, fixture: fixture))

        guard case .failed = result else {
            XCTFail("Expected the scheduled run to fail")
            return
        }
        XCTAssertEqual(run.status, .failure)
        XCTAssertEqual(run.finishedAt, Date(timeIntervalSinceReferenceDate: 2_000))
        XCTAssertNotNil(run.lastError)
        XCTAssertTrue(fixture.conversation.isUnread)
        guard case .error = notificationManager.handledEvents.first?.event else {
            return XCTFail("Expected one durable failure notification")
        }
        XCTAssertEqual(notificationManager.handledEvents.count, 1)
        XCTAssertEqual(notifiedRunStatus, .failure)
        XCTAssertTrue(notificationConversationWasUnread)
        XCTAssertEqual(suspensionCountAtNotification, 1)
    }

    func testWaitingStateSaveFailurePersistsTerminalFailureBeforeSuspension() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let run = try attachRun(to: fixture, status: .preparing)
        let suspension = ScheduledExecutionSuspensionRecorder(
            conversation: fixture.conversation,
            run: run
        )
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in },
            suspendRuntime: { _ in suspension.recordSuspension() },
            runtimeIsSuspended: { _ in true }
        )
        var saveCount = 0
        let executor = DefaultScheduledTaskRunExecutor(
            modelContext: fixture.context,
            controllerRegistry: registry,
            notificationManager: makeNotificationManager(fixture: fixture),
            startAutomatedTurn: { viewModel, _ in
                viewModel.markVisibleTurnStarted()
                viewModel.turnState.beginTurn()
            },
            saveExecutionState: {
                saveCount += 1
                if saveCount == 2 {
                    throw ScheduledTaskExecutorTestError.saveFailed
                }
                try fixture.context.save()
            }
        )
        let execution = Task {
            try await executor.execute(makeMaterialization(run: run, fixture: fixture))
        }
        try await waitUntil("expected scheduled run to start") { run.status == .running }

        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: makeToolApproval(), status: .pending)
        try await waitUntil("expected provider cancellation after the save failure") {
            await fixture.agentsManager.cancelCalls().isEmpty == false
        }
        fixture.viewModel.state.pendingToolApproval = nil
        fixture.viewModel.state.lastTurnInterrupted = true
        fixture.viewModel.state.endTurn()
        let result = try await execution.value

        guard case .failed = result else {
            return XCTFail("Expected waiting-state persistence to fail the run")
        }
        XCTAssertEqual(run.status, .failure)
        XCTAssertTrue(fixture.conversation.isUnread)
        XCTAssertEqual(suspension.observations.first?.runStatus, .failure)
    }

    func testFirstPublishedWaitingOutcomeStillBindsAndFinishesRun() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let run = try attachRun(to: fixture, status: .preparing)
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in },
            suspendRuntime: { _ in },
            runtimeIsSuspended: { _ in true }
        )
        let approval = makeToolApproval()
        let executor = DefaultScheduledTaskRunExecutor(
            modelContext: fixture.context,
            controllerRegistry: registry,
            notificationManager: makeNotificationManager(fixture: fixture),
            startAutomatedTurn: { viewModel, _ in
                viewModel.markVisibleTurnStarted()
                viewModel.turnState.beginTurn()
                viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
            }
        )

        let execution = Task {
            try await executor.execute(makeMaterialization(run: run, fixture: fixture))
        }
        try await waitUntil("expected first waiting outcome to persist") {
            run.status == .waiting
        }
        fixture.viewModel.state.pendingToolApproval = nil
        fixture.viewModel.state.endTurn()

        let result = try await execution.value
        XCTAssertEqual(result, .succeeded)
        XCTAssertEqual(run.status, .success)
    }

    func testUserStopCancelsActiveProviderWithoutMutatingDefinitionCadence() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let definition = ScheduledTask(
            id: "definition",
            title: "Scheduled task",
            prompt: "Run scheduled work.",
            recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: "America/Chicago",
            providerID: "claude",
            effort: "medium",
            permissionMode: "default",
            nextOccurrenceAt: Date(timeIntervalSinceReferenceDate: 10_000),
            pendingOccurrenceAt: Date(timeIntervalSinceReferenceDate: 9_000)
        )
        let nextOccurrenceAt = definition.nextOccurrenceAt
        let run = try attachRun(to: fixture, status: .preparing)
        run.scheduledTask = definition
        definition.runs = [run]
        fixture.context.insert(definition)
        try fixture.context.save()
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
            }
        )
        let execution = Task {
            try await executor.execute(makeMaterialization(run: run, fixture: fixture))
        }
        try await waitUntil("expected scheduled run to start before stopping") {
            run.status == .running
        }

        try await executor.stop(runID: run.persistentModelID)
        fixture.viewModel.state.endTurn()
        let result = try await execution.value

        XCTAssertEqual(definition.pendingOccurrenceAt, Date(timeIntervalSinceReferenceDate: 9_000))
        XCTAssertEqual(definition.nextOccurrenceAt, nextOccurrenceAt)
        XCTAssertEqual(result, .interrupted)
        XCTAssertEqual(run.status, .interrupted)
        let cancelCalls = await fixture.agentsManager.cancelCalls()
        XCTAssertEqual(cancelCalls, [fixture.conversation.id])
    }

    func testTaskCancellationCancelsProviderAndPersistsInterruptionBeforeReturning() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let run = try attachRun(to: fixture, status: .preparing)
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
            }
        )
        let execution = Task {
            try await executor.execute(makeMaterialization(run: run, fixture: fixture))
        }
        try await waitUntil("expected scheduled run to start before cancellation") {
            run.status == .running
        }

        execution.cancel()
        try await waitUntil("expected provider cancellation request") {
            await fixture.agentsManager.cancelCalls().isEmpty == false
        }
        fixture.viewModel.state.lastTurnInterrupted = true
        fixture.viewModel.state.endTurn()
        let result = try await execution.value

        XCTAssertEqual(result, .interrupted)
        XCTAssertEqual(run.status, .interrupted)
        XCTAssertTrue(fixture.conversation.isUnread)
        XCTAssertEqual(suspension.observations.count, 1)
        let cancelCalls = await fixture.agentsManager.cancelCalls()
        XCTAssertTrue(cancelCalls.contains(fixture.conversation.id))
    }

    func testStopForHistoricalRunDoesNotCancelProviderOrMutateNewerPendingWork() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let definition = ScheduledTask(
            id: "definition",
            title: "Scheduled task",
            prompt: "Run scheduled work.",
            recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: "America/Chicago",
            providerID: "claude",
            effort: "medium",
            permissionMode: "default",
            pendingOccurrenceAt: Date(timeIntervalSinceReferenceDate: 12_000)
        )
        let run = try attachRun(to: fixture, status: .success)
        run.scheduledTask = definition
        definition.runs = [run]
        fixture.context.insert(definition)
        try fixture.context.save()
        let registry = DefaultConversationControllerRegistry { _ in fixture.viewModel }
        let executor = DefaultScheduledTaskRunExecutor(
            modelContext: fixture.context,
            controllerRegistry: registry,
            notificationManager: makeNotificationManager(fixture: fixture)
        )

        try await executor.stop(runID: run.persistentModelID)

        XCTAssertEqual(definition.pendingOccurrenceAt, Date(timeIntervalSinceReferenceDate: 12_000))
        let cancelCalls = await fixture.agentsManager.cancelCalls()
        XCTAssertTrue(cancelCalls.isEmpty)
    }
}

extension ScheduledTaskRunExecutorTests {
    func makeProjectLocalScheduledTaskFixture() throws -> ConversationViewModelTestFixture {
        let fixture = try ConversationViewModelTestFixture()
        let projectPath = fixture.project.path
        fixture.thread.mode = .task
        fixture.thread.taskWorkspaceDescriptor = TaskWorkspaceDescriptor(
            primaryRoot: projectPath,
            ownershipStrategy: .projectLocal,
            sourceProjectPath: projectPath
        )
        fixture.thread.project = nil
        try fixture.context.save()
        return fixture
    }

    func attachRun(
        to fixture: ConversationViewModelTestFixture,
        status: ScheduledTaskRunStatus,
        workspaceKind: ScheduledTaskWorkspaceKind = .privateWorkspace,
        workspaceStrategy: ScheduledTaskWorkspaceStrategy = .worktree
    ) throws -> ScheduledTaskRun {
        let run = makeScheduledTaskRun(
            status: status,
            workspaceKind: workspaceKind,
            workspaceStrategy: workspaceStrategy,
            projectPath: workspaceKind == .project ? fixture.project.path : nil
        )
        run.thread = fixture.thread
        fixture.thread.scheduledTaskRun = run
        fixture.context.insert(run)
        try fixture.context.save()
        return run
    }

    func makeMaterialization(
        run: ScheduledTaskRun,
        fixture: ConversationViewModelTestFixture
    ) -> ScheduledTaskRunMaterialization {
        ScheduledTaskRunMaterialization(
            runID: run.persistentModelID,
            threadID: fixture.thread.persistentModelID,
            conversationID: fixture.conversation.id,
            prompt: run.promptSnapshot,
            workspace: TaskWorkspaceDescriptor(
                primaryRoot: fixture.project.path,
                ownershipStrategy: .projectLocal,
                sourceProjectPath: fixture.project.path
            )
        )
    }

    func makeNotificationManager(
        fixture: ConversationViewModelTestFixture
    ) -> DefaultNotificationManager {
        let manager = DefaultNotificationManager(
            settingsService: fixture.settingsService,
            modelContainer: fixture.container,
            systemNotificationCenter: NotificationCenter()
        )
        manager.setBadgeCount = { _ in }
        manager.onDismissDelivered = { _ in }
        return manager
    }

    func makeToolApproval() -> ToolApprovalRequest {
        ToolApprovalRequest(
            sessionId: "session-1",
            toolUseId: "approval-1",
            toolName: "Bash",
            toolInput: "{}"
        )
    }

    func assertTerminalActivity(run: ScheduledTaskRun, thread: AgentThread, at date: Date) {
        XCTAssertEqual(run.finishedAt, date)
        XCTAssertEqual(thread.modifiedAt, date)
    }
}

enum ScheduledTaskExecutorTestError: Error {
    case launchFailed
    case saveFailed
}

@MainActor
final class ScheduledExecutionSuspensionRecorder {
    struct Observation {
        let conversationWasUnread: Bool
        let runStatus: ScheduledTaskRunStatus?
    }

    private let conversation: Conversation
    private let run: ScheduledTaskRun?
    private(set) var observations: [Observation] = []

    init(conversation: Conversation, run: ScheduledTaskRun? = nil) {
        self.conversation = conversation
        self.run = run
    }

    func recordSuspension() {
        observations.append(Observation(
            conversationWasUnread: conversation.isUnread,
            runStatus: run?.status
        ))
    }
}

@MainActor
private func makeScheduledTaskRun(
    status: ScheduledTaskRunStatus,
    workspaceKind: ScheduledTaskWorkspaceKind = .privateWorkspace,
    workspaceStrategy: ScheduledTaskWorkspaceStrategy = .worktree,
    projectPath: String? = nil
) -> ScheduledTaskRun {
    ScheduledTaskRun(
        occurrenceID: UUID().uuidString,
        definitionID: "definition",
        definitionRevision: 1,
        occurrenceAt: Date(timeIntervalSinceReferenceDate: 900),
        triggerKind: .scheduled,
        status: status,
        titleSnapshot: "Scheduled task",
        promptSnapshot: "Run scheduled work.",
        timeZoneIdentifierSnapshot: "America/Chicago",
        providerIDSnapshot: "claude",
        effortSnapshot: "medium",
        permissionModeSnapshot: "default",
        workspaceKindSnapshot: workspaceKind,
        workspaceStrategySnapshot: workspaceStrategy,
        projectPathSnapshot: projectPath
    )
}

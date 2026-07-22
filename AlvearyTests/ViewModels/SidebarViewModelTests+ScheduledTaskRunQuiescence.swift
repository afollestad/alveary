import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testArchiveScheduledTaskWaitsForPrelaunchCoordinatorBeforeCommit() async throws {
        let gate = SidebarScheduledRunQuiescenceGate()
        let fixture = try SidebarTestFixture(
            stopAndWaitForScheduledTaskRun: { runID in
                await gate.stopAndWait(runID: runID)
            }
        )
        let (thread, run) = try insertScheduledTaskThread(
            fixture: fixture,
            status: .preparing,
            conversationID: "scheduled-prelaunch-archive"
        )

        let archive = Task { @MainActor in
            try await fixture.viewModel.archiveThread(thread)
        }
        await gate.waitUntilEntered()

        XCTAssertEqual(gate.runID, run.persistentModelID)
        XCTAssertNil(try fixture.requireThread(thread).archivedAt)
        XCTAssertNotNil(fixture.context.resolveConversation(conversationID: "scheduled-prelaunch-archive"))

        run.status = .interrupted
        run.finishedAt = Date()
        try fixture.context.save()
        gate.release()
        try await archive.value

        XCTAssertNotNil(try fixture.requireThread(thread).archivedAt)
        XCTAssertEqual(run.status, .interrupted)
    }

    func testDeleteScheduledTaskWaitsForPrelaunchCoordinatorBeforeCommit() async throws {
        let gate = SidebarScheduledRunQuiescenceGate()
        let fixture = try SidebarTestFixture(
            stopAndWaitForScheduledTaskRun: { runID in
                await gate.stopAndWait(runID: runID)
            }
        )
        let (thread, run) = try insertScheduledTaskThread(
            fixture: fixture,
            status: .preparing,
            conversationID: "scheduled-prelaunch-delete"
        )
        let threadID = thread.persistentModelID
        let runID = run.persistentModelID

        let deletion = Task { @MainActor in
            try await fixture.viewModel.deleteThread(thread)
        }
        await gate.waitUntilEntered()

        XCTAssertEqual(gate.runID, runID)
        XCTAssertNotNil(fixture.context.resolveThread(id: threadID))
        XCTAssertNotNil(fixture.context.resolveConversation(conversationID: "scheduled-prelaunch-delete"))

        run.status = .interrupted
        run.finishedAt = Date()
        try fixture.context.save()
        gate.release()
        try await deletion.value

        XCTAssertNil(fixture.context.resolveThread(id: threadID))
        XCTAssertNil(fixture.context.resolveConversation(conversationID: "scheduled-prelaunch-delete"))
        let retainedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: runID))
        XCTAssertEqual(retainedRun.status, .interrupted)
        XCTAssertNil(retainedRun.thread)
    }

    func testArchiveTerminalScheduledTaskWaitsForRuntimeFinalizationBeforeCommit() async throws {
        let fixture = try SidebarActiveScheduledExecutionFixture(blocksRuntimeSuspension: true)
        try fixture.start()
        try await waitUntil("expected the scheduled executor to become active") {
            fixture.run.status == .running
        }
        fixture.finishProviderTurn()
        try await waitUntil("expected the scheduled result to persist before suspension") {
            fixture.run.status == .success
        }
        let suspensionGate = try XCTUnwrap(fixture.runtimeSuspensionGate)
        await suspensionGate.waitUntilEntered()
        var archiveTask: Task<Void, Error>?

        do {
            let archive = Task { @MainActor in
                try await fixture.sidebarViewModel.archiveThread(fixture.thread)
            }
            archiveTask = archive
            await fixture.stopBridge.waitUntilWaitOnlyEntered()

            XCTAssertNil(fixture.thread.archivedAt)
            XCTAssertNotNil(fixture.modelContext.resolveConversation(conversationID: fixture.conversation.id))
            XCTAssertTrue(fixture.notificationManager.handledEvents.isEmpty)

            suspensionGate.release()
            try await archive.value

            XCTAssertNotNil(fixture.thread.archivedAt)
            XCTAssertEqual(fixture.notificationManager.handledEvents.map(\.event), [.stop(message: nil)])
            XCTAssertEqual(fixture.notificationObservation.conversationExistedAtNotification, true)
        } catch {
            suspensionGate.release()
            if let archiveTask {
                _ = await archiveTask.result
            }
            throw error
        }
    }

    func testDeleteTerminalScheduledTaskWaitsForNotificationBeforeConversationRemoval() async throws {
        let fixture = try SidebarActiveScheduledExecutionFixture(blocksRuntimeSuspension: true)
        try fixture.start()
        try await waitUntil("expected the scheduled executor to become active") {
            fixture.run.status == .running
        }
        fixture.finishProviderTurn()
        try await waitUntil("expected the scheduled result to persist before suspension") {
            fixture.run.status == .success
        }
        let suspensionGate = try XCTUnwrap(fixture.runtimeSuspensionGate)
        await suspensionGate.waitUntilEntered()
        let threadID = fixture.thread.persistentModelID
        let conversationID = fixture.conversation.id
        var deletionTask: Task<Void, Error>?

        do {
            let deletion = Task { @MainActor in
                try await fixture.sidebarViewModel.deleteThread(fixture.thread)
            }
            deletionTask = deletion
            await fixture.stopBridge.waitUntilWaitOnlyEntered()

            XCTAssertNotNil(fixture.modelContext.resolveThread(id: threadID))
            XCTAssertNotNil(fixture.modelContext.resolveConversation(conversationID: conversationID))
            XCTAssertTrue(fixture.notificationManager.handledEvents.isEmpty)

            suspensionGate.release()
            try await deletion.value

            XCTAssertNil(fixture.modelContext.resolveThread(id: threadID))
            XCTAssertNil(fixture.modelContext.resolveConversation(conversationID: conversationID))
            XCTAssertEqual(fixture.notificationManager.handledEvents.map(\.event), [.stop(message: nil)])
            XCTAssertEqual(fixture.notificationObservation.conversationExistedAtNotification, true)
        } catch {
            suspensionGate.release()
            if let deletionTask {
                _ = await deletionTask.result
            }
            throw error
        }
    }

    func testDeleteActiveScheduledTaskLetsExecutorPersistInterruptionBeforeConversationRemoval() async throws {
        let fixture = try SidebarActiveScheduledExecutionFixture()
        try fixture.start()
        try await waitUntil("expected the scheduled executor to become active") {
            fixture.run.status == .running
        }
        let threadID = fixture.thread.persistentModelID
        let runID = fixture.run.persistentModelID

        try await fixture.sidebarViewModel.deleteThread(fixture.thread)

        let executionResult = try await fixture.executionResult()
        XCTAssertEqual(executionResult, .interrupted)
        XCTAssertNil(fixture.modelContext.resolveThread(id: threadID))
        XCTAssertNil(fixture.modelContext.resolveConversation(conversationID: fixture.conversation.id))
        let retainedRun = try XCTUnwrap(fixture.modelContext.resolveScheduledTaskRun(id: runID))
        XCTAssertEqual(retainedRun.status, .interrupted)
        XCTAssertNil(retainedRun.lastError)
        XCTAssertNil(retainedRun.thread)
    }
}

@MainActor
final class SidebarScheduledRunQuiescenceGate {
    private(set) var runID: PersistentIdentifier?
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func stopAndWait(runID: PersistentIdentifier) async {
        self.runID = runID
        let waiters = enteredWaiters
        enteredWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilEntered() async {
        guard runID == nil else {
            return
        }
        await withCheckedContinuation { continuation in
            enteredWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
private final class SidebarActiveScheduledExecutionFixture {
    let conversationFixture: ConversationViewModelTestFixture
    let run: ScheduledTaskRun
    let sidebarViewModel: SidebarViewModel
    let executor: DefaultScheduledTaskRunExecutor
    let stopBridge: SidebarScheduledExecutionStopBridge
    let runtimeSuspensionGate: SidebarScheduledRuntimeSuspensionGate?
    let notificationManager: ScheduledExecutionNotificationRecorder
    let notificationObservation: SidebarScheduledNotificationObservation
    private var execution: Task<ScheduledTaskRunExecutionResult, Error>?

    var modelContext: ModelContext { conversationFixture.context }
    var thread: AgentThread { conversationFixture.thread }
    var conversation: Conversation { conversationFixture.conversation }

    init(blocksRuntimeSuspension: Bool = false) throws {
        let projectPath = "/tmp/alveary-project"
        let conversationFixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false,
            threadMode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: projectPath,
                ownershipStrategy: .projectLocal,
                sourceProjectPath: projectPath
            )
        )
        let run = makeActiveScheduledRun(projectPath: projectPath, thread: conversationFixture.thread)
        conversationFixture.context.insert(run)
        try conversationFixture.context.save()
        let runtimeSuspensionGate = blocksRuntimeSuspension ? SidebarScheduledRuntimeSuspensionGate() : nil
        let registry = makeSidebarScheduledControllerRegistry(fixture: conversationFixture, runtimeSuspensionGate: runtimeSuspensionGate)
        let (notificationManager, notificationObservation) = makeSidebarScheduledNotificationManager(fixture: conversationFixture)
        let stopBridge = SidebarScheduledExecutionStopBridge()
        let executor = DefaultScheduledTaskRunExecutor(
            modelContext: conversationFixture.context,
            controllerRegistry: registry,
            notificationManager: notificationManager,
            startAutomatedTurn: { viewModel, _ in
                viewModel.markVisibleTurnStarted()
                viewModel.turnState.beginTurn()
            }
        )
        let sidebarViewModel = SidebarViewModel(
            agentsManager: conversationFixture.agentsManager,
            modelContext: conversationFixture.context,
            shell: MockShellRunner(),
            gitHubCLI: SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false),
            worktreeManager: SidebarMockWorktreeManager(),
            settingsService: conversationFixture.settingsService,
            attachmentStore: RecordingConversationAttachmentStore(),
            stopAndWaitForScheduledTaskRun: { runID in
                try await stopBridge.stopAndWait(runID: runID)
            },
            notificationManager: notificationManager
        )
        self.conversationFixture = conversationFixture
        self.run = run
        self.sidebarViewModel = sidebarViewModel
        self.executor = executor
        self.stopBridge = stopBridge
        self.runtimeSuspensionGate = runtimeSuspensionGate
        self.notificationManager = notificationManager
        self.notificationObservation = notificationObservation
    }

    func start() throws {
        let workspace = try XCTUnwrap(thread.taskWorkspaceDescriptor)
        let materialization = ScheduledTaskRunMaterialization(
            runID: run.persistentModelID,
            threadID: thread.persistentModelID,
            conversationID: conversation.id,
            prompt: run.promptSnapshot,
            workspace: workspace
        )
        let execution = Task { try await executor.execute(materialization) }
        self.execution = execution
        stopBridge.install(
            executor: executor,
            execution: execution,
            viewModel: conversationFixture.viewModel
        )
    }

    func executionResult() async throws -> ScheduledTaskRunExecutionResult {
        guard let execution else {
            throw SidebarScheduledExecutionTestError.notStarted
        }
        return try await execution.value
    }

    func finishProviderTurn() {
        conversationFixture.viewModel.state.endTurn()
    }
}

@MainActor
private final class SidebarScheduledExecutionStopBridge {
    private var executor: DefaultScheduledTaskRunExecutor?
    private var execution: Task<ScheduledTaskRunExecutionResult, Error>?
    private var viewModel: ConversationViewModel?
    private var waitOnlyRunID: PersistentIdentifier?
    private var waitOnlyEntryContinuations: [CheckedContinuation<Void, Never>] = []

    func install(
        executor: DefaultScheduledTaskRunExecutor,
        execution: Task<ScheduledTaskRunExecutionResult, Error>,
        viewModel: ConversationViewModel
    ) {
        self.executor = executor
        self.execution = execution
        self.viewModel = viewModel
    }

    func stopAndWait(runID: PersistentIdentifier) async throws {
        guard let executor, let execution, let viewModel else {
            throw SidebarScheduledExecutionTestError.notStarted
        }
        if viewModel.conversation.thread?.scheduledTaskRun?.status.isTerminal == true {
            waitOnlyRunID = runID
            let continuations = waitOnlyEntryContinuations
            waitOnlyEntryContinuations.removeAll()
            continuations.forEach { $0.resume() }
            _ = try await execution.value
            return
        }
        try await executor.stop(runID: runID)
        viewModel.state.lastTurnInterrupted = true
        viewModel.state.endTurn()
        _ = try await execution.value
    }

    func waitUntilWaitOnlyEntered() async {
        guard waitOnlyRunID == nil else {
            return
        }
        await withCheckedContinuation { continuation in
            waitOnlyEntryContinuations.append(continuation)
        }
    }
}

@MainActor
private final class SidebarScheduledRuntimeSuspensionGate {
    private(set) var isSuspended = false
    private var entered = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        guard !isSuspended else {
            return
        }
        entered = true
        let waiters = enteredWaiters
        enteredWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        isSuspended = true
    }

    func waitUntilEntered() async {
        guard !entered else {
            return
        }
        await withCheckedContinuation { continuation in
            enteredWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
private final class SidebarScheduledNotificationObservation {
    var conversationExistedAtNotification: Bool?
}

@MainActor
private func makeSidebarScheduledControllerRegistry(
    fixture: ConversationViewModelTestFixture,
    runtimeSuspensionGate: SidebarScheduledRuntimeSuspensionGate?
) -> DefaultConversationControllerRegistry {
    DefaultConversationControllerRegistry(
        makeViewModel: { _ in fixture.viewModel },
        flushTerminalRecords: { _ in },
        suspendRuntime: { _ in
            await runtimeSuspensionGate?.suspend()
        },
        runtimeIsSuspended: { _ in
            runtimeSuspensionGate?.isSuspended ?? true
        }
    )
}

@MainActor
private func makeSidebarScheduledNotificationManager(
    fixture: ConversationViewModelTestFixture
) -> (ScheduledExecutionNotificationRecorder, SidebarScheduledNotificationObservation) {
    let manager = ScheduledExecutionNotificationRecorder()
    let observation = SidebarScheduledNotificationObservation()
    manager.onHandleEvent = { _, conversationID in
        observation.conversationExistedAtNotification = fixture.context
            .resolveConversation(conversationID: conversationID) != nil
    }
    return (manager, observation)
}

private enum SidebarScheduledExecutionTestError: Error {
    case notStarted
}

@MainActor
private func makeActiveScheduledRun(projectPath: String, thread: AgentThread) -> ScheduledTaskRun {
    let run = ScheduledTaskRun(
        occurrenceID: UUID().uuidString,
        definitionID: "definition-\(UUID().uuidString)",
        definitionRevision: 1,
        occurrenceAt: Date(timeIntervalSince1970: 1_800_000_000),
        triggerKind: .scheduled,
        status: .preparing,
        titleSnapshot: "Scheduled task",
        promptSnapshot: "Run scheduled work.",
        timeZoneIdentifierSnapshot: "America/Chicago",
        providerIDSnapshot: "codex",
        effortSnapshot: "high",
        permissionModeSnapshot: "default",
        workspaceKindSnapshot: .project,
        workspaceStrategySnapshot: .localCheckout,
        projectPathSnapshot: projectPath,
        thread: thread
    )
    thread.scheduledTaskRun = run
    return run
}

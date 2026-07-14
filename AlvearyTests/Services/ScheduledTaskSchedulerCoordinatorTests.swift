import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ScheduledTaskSchedulerCoordinatorTests: XCTestCase {
    func testOverlappingWorkspaceExecutionsSerialize() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        try fixture.insertDefinition(id: "parent", projectPath: "/tmp/scheduler-root")
        try fixture.insertDefinition(id: "child", projectPath: "/tmp/scheduler-root/nested")
        let executionProbe = ScheduledTaskBlockingProbe()
        let services = fixture.makeServices(executionProbe: executionProbe)

        XCTAssertEqual(try services.coordinator.startDueTasks(at: fixture.actionDate), 2)
        try await waitUntil("expected one overlapping execution to start") {
            await executionProbe.snapshot().entryCount == 1
        }
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        var snapshot = await executionProbe.snapshot()
        XCTAssertEqual(snapshot.entryCount, 1)
        XCTAssertEqual(snapshot.maximumConcurrentCount, 1)

        await executionProbe.release()
        try await waitUntil("expected the serialized execution to start") {
            await executionProbe.snapshot().entryCount == 2
        }
        await executionProbe.release()
        await services.coordinator.waitUntilIdle()

        snapshot = await executionProbe.snapshot()
        XCTAssertEqual(snapshot.maximumConcurrentCount, 1)
        XCTAssertTrue(try fixture.runs().allSatisfy { $0.status == .success })
    }

    func testDisjointWorkspaceExecutionsRunConcurrently() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        try fixture.insertDefinition(id: "first", projectPath: "/tmp/scheduler-first")
        try fixture.insertDefinition(id: "second", projectPath: "/tmp/scheduler-second")
        let executionProbe = ScheduledTaskBlockingProbe()
        let services = fixture.makeServices(executionProbe: executionProbe)

        XCTAssertEqual(try services.coordinator.startDueTasks(at: fixture.actionDate), 2)
        try await waitUntil("expected disjoint executions to start together") {
            await executionProbe.snapshot().entryCount == 2
        }
        let snapshot = await executionProbe.snapshot()
        XCTAssertEqual(snapshot.maximumConcurrentCount, 2)

        await executionProbe.release(count: 2)
        await services.coordinator.waitUntilIdle()
        XCTAssertTrue(try fixture.runs().allSatisfy { $0.status == .success })
    }

    func testSameSourceProjectSerializesWorktreeMaterialization() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let project = Project(path: "/tmp/scheduler-source", name: "Shared source")
        fixture.context.insert(project)
        try fixture.insertDefinition(id: "first", project: project, workspaceStrategy: .worktree)
        try fixture.insertDefinition(id: "second", project: project, workspaceStrategy: .worktree)
        let materializationProbe = ScheduledTaskBlockingProbe()
        let services = fixture.makeServices(materializationProbe: materializationProbe)

        XCTAssertEqual(try services.coordinator.startDueTasks(at: fixture.actionDate), 2)
        try await waitUntil("expected one worktree materialization to start") {
            await materializationProbe.snapshot().entryCount == 1
        }
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        var snapshot = await materializationProbe.snapshot()
        XCTAssertEqual(snapshot.entryCount, 1)
        XCTAssertEqual(snapshot.maximumConcurrentCount, 1)

        await materializationProbe.release()
        try await waitUntil("expected the second worktree materialization to start") {
            await materializationProbe.snapshot().entryCount == 2
        }
        await materializationProbe.release()
        await services.coordinator.waitUntilIdle()

        snapshot = await materializationProbe.snapshot()
        XCTAssertEqual(snapshot.maximumConcurrentCount, 1)
        XCTAssertTrue(try fixture.runs().allSatisfy { $0.status == .success })
    }

    func testRunNowClaimsAndExecutesRequestedOccurrence() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let definition = try fixture.insertDefinition(id: "run-now", projectPath: "/tmp/run-now")
        let services = fixture.makeServices()
        let request = ScheduledTaskRunNowRequest(
            definitionID: definition.id,
            definitionRevision: definition.revision,
            occurrenceAt: fixture.actionDate,
            triggeredAt: fixture.actionDate,
            occurrenceSource: .scheduled
        )

        XCTAssertTrue(services.coordinator.startRunNow(request))
        await services.coordinator.waitUntilIdle()

        let run = try XCTUnwrap(fixture.runs().first)
        XCTAssertEqual(run.triggerKind, .runNow)
        XCTAssertEqual(run.occurrenceAt, fixture.actionDate)
        XCTAssertEqual(run.status, .success)
        XCTAssertEqual(definition.state, .completed)
    }

    func testActiveDefinitionWithoutAnOccurrenceIsValidatedAndPaused() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let definition = try fixture.insertDefinition(id: "invalid-no-occurrence", projectPath: "/tmp/invalid-no-occurrence")
        definition.nextOccurrenceAt = nil
        definition.timeZoneIdentifier = "invalid/timezone"
        try fixture.context.save()
        let services = fixture.makeServices()

        XCTAssertEqual(try services.coordinator.startDueTasks(at: fixture.actionDate), 1)
        await services.coordinator.waitUntilIdle()

        XCTAssertEqual(definition.state, .paused)
        XCTAssertTrue(definition.pauseReason?.contains("Unknown IANA time zone") == true)
        XCTAssertTrue(try fixture.runs().isEmpty)
    }

    func testUnknownDefinitionStateWithoutAnOccurrenceIsDurablyPaused() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let definition = try fixture.insertDefinition(id: "unknown-state", projectPath: "/tmp/unknown-state")
        definition.stateRawValue = "future-state"
        definition.nextOccurrenceAt = nil
        definition.pendingOccurrenceAt = nil
        let originalRevision = definition.revision
        try fixture.context.save()
        let services = fixture.makeServices()

        XCTAssertEqual(try services.coordinator.startDueTasks(at: fixture.actionDate), 1)
        await services.coordinator.waitUntilIdle()

        let verificationContext = ModelContext(fixture.container)
        let persistedDefinition = try XCTUnwrap(verificationContext.resolveScheduledTask(id: definition.id))
        XCTAssertEqual(persistedDefinition.stateRawValue, ScheduledTaskState.paused.rawValue)
        XCTAssertEqual(persistedDefinition.pauseReason, "Scheduled task state is invalid.")
        XCTAssertEqual(persistedDefinition.lastError, "Scheduled task state is invalid.")
        XCTAssertEqual(persistedDefinition.revision, originalRevision + 1)
        XCTAssertTrue(try fixture.runs().isEmpty)
    }

    func testResumeClaimedRunsLaunchesOnlyClaimedIDs() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let claimedDefinition = try fixture.insertDefinition(id: "claimed", projectPath: "/tmp/claimed")
        let preparingDefinition = try fixture.insertDefinition(id: "preparing", projectPath: "/tmp/preparing")
        let claimedRun = try fixture.insertRun(definition: claimedDefinition, status: .claimed)
        let preparingRun = try fixture.insertRun(definition: preparingDefinition, status: .preparing)
        let services = fixture.makeServices()

        let resumedCount = services.coordinator.resumeClaimedRuns([
            claimedRun.persistentModelID,
            preparingRun.persistentModelID
        ])
        XCTAssertEqual(resumedCount, 1)
        await services.coordinator.waitUntilIdle()

        XCTAssertEqual(claimedRun.status, .success)
        XCTAssertEqual(preparingRun.status, .preparing)
    }

    func testMaterializationAndExecutionFailuresArePersistedAsTerminal() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        try fixture.insertDefinition(id: "materialization", projectPath: "/tmp/materialization-failure")
        var services = fixture.makeServices(
            materializationFailureIDs: ["materialization"]
        )

        XCTAssertEqual(try services.coordinator.startDueTasks(at: fixture.actionDate), 1)
        await services.coordinator.waitUntilIdle()
        var run = try XCTUnwrap(fixture.runs().first)
        XCTAssertEqual(run.status, .failure)
        XCTAssertNotNil(run.finishedAt)
        XCTAssertEqual(run.lastError, ScheduledTaskCoordinatorTestError.materialization.localizedDescription)
        XCTAssertEqual(run.thread?.modifiedAt, fixture.actionDate.addingTimeInterval(1))

        try fixture.insertDefinition(id: "execution", projectPath: "/tmp/execution-failure")
        services = fixture.makeServices(executionFailureIDs: ["execution"])
        XCTAssertEqual(try services.coordinator.startDueTasks(at: fixture.actionDate), 1)
        await services.coordinator.waitUntilIdle()

        run = try XCTUnwrap(fixture.runs().first { $0.definitionID == "execution" })
        XCTAssertEqual(run.status, .failure)
        XCTAssertNotNil(run.finishedAt)
        XCTAssertEqual(run.lastError, ScheduledTaskCoordinatorTestError.execution.localizedDescription)
        XCTAssertEqual(run.thread?.modifiedAt, fixture.actionDate.addingTimeInterval(1))
    }

    func testStopDelegatesToExecutorClearsPendingAndTracksUntilInterrupted() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let definition = try fixture.insertDefinition(id: "stop", projectPath: "/tmp/stop")
        let executionProbe = ScheduledTaskBlockingProbe()
        let services = fixture.makeServices(executionProbe: executionProbe)

        XCTAssertEqual(try services.coordinator.startDueTasks(at: fixture.actionDate), 1)
        try await waitUntil("expected execution before stop") {
            await executionProbe.snapshot().entryCount == 1
        }
        let run = try XCTUnwrap(fixture.runs().first)
        definition.pendingOccurrenceAt = fixture.actionDate
        try fixture.context.save()
        XCTAssertTrue(services.coordinator.isActive(runID: run.persistentModelID))

        try await services.coordinator.stop(runID: run.persistentModelID)
        await services.coordinator.waitUntilIdle()

        XCTAssertEqual(services.executor.stopRunIDs, [run.persistentModelID])
        XCTAssertEqual(run.status, .interrupted)
        XCTAssertNil(definition.pendingOccurrenceAt)
        XCTAssertFalse(services.coordinator.isActive(runID: run.persistentModelID))
        XCTAssertTrue(services.coordinator.activeRunIDs.isEmpty)
    }
}

@MainActor
struct ScheduledTaskCoordinatorFixture {
    let container: ModelContainer
    let context: ModelContext
    let actionDate = Date(timeIntervalSinceReferenceDate: 10_000)

    init() throws {
        container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    @discardableResult
    func insertDefinition(
        id: String,
        projectPath: String,
        workspaceStrategy: ScheduledTaskWorkspaceStrategy = .localCheckout
    ) throws -> ScheduledTask {
        let project = Project(path: projectPath, name: id)
        context.insert(project)
        return try insertDefinition(id: id, project: project, workspaceStrategy: workspaceStrategy)
    }

    @discardableResult
    func insertDefinition(
        id: String,
        project: Project,
        workspaceStrategy: ScheduledTaskWorkspaceStrategy
    ) throws -> ScheduledTask {
        let definition = ScheduledTask(
            id: id,
            title: "Task \(id)",
            prompt: "Perform \(id).",
            recurrence: .once(actionDate),
            timeZoneIdentifier: "UTC",
            providerID: "codex",
            effort: "high",
            permissionMode: "acceptEdits",
            workspaceKind: .project,
            workspaceStrategy: workspaceStrategy,
            project: project,
            nextOccurrenceAt: actionDate
        )
        context.insert(definition)
        try context.save()
        return definition
    }

    func makeServices(
        materializationProbe: ScheduledTaskBlockingProbe? = nil,
        executionProbe: ScheduledTaskBlockingProbe? = nil,
        stopProbe: ScheduledTaskBlockingProbe? = nil,
        materializationFailureIDs: Set<String> = [],
        provenanceFailureIDs: Set<String> = [],
        executionFailureIDs: Set<String> = [],
        preflightValidator: @escaping ScheduledTaskPreflightValidator = { snapshot in
            scheduledTaskReadyOutcome(for: snapshot)
        },
        keepAwakeService: RecordingKeepAwakeService = RecordingKeepAwakeService(),
        notificationManager: RecordingNotificationManager = RecordingNotificationManager(),
        terminalConversationReconciliation: @escaping ScheduledTaskSchedulerCoordinator.TerminalConversationReconciliation = { _ in },
        definitionFailureNotification: @escaping ScheduledTaskSchedulerCoordinator.DefinitionFailureNotification = { _, _, _ in },
        clearPendingOccurrence: ScheduledTaskSchedulerCoordinator.PendingOccurrenceClearer? = nil,
        savePendingOccurrenceState: ScheduledTaskSchedulerCoordinator.PendingOccurrenceStateSaver? = nil,
        saveTerminalState: ScheduledTaskSchedulerCoordinator.TerminalStateSaver? = nil,
        persistenceRetryWait: @escaping ScheduledTaskSchedulerCoordinator.PersistenceRetryWait = {}
    ) -> ScheduledTaskCoordinatorServices {
        let materializer = ScheduledTaskCoordinatorMaterializer(
            modelContext: context,
            probe: materializationProbe,
            failureDefinitionIDs: materializationFailureIDs,
            provenanceFailureIDs: provenanceFailureIDs
        )
        let executor = ScheduledTaskCoordinatorExecutor(
            modelContext: context,
            probe: executionProbe,
            stopProbe: stopProbe,
            failureDefinitionIDs: executionFailureIDs
        )
        let engine = ScheduledTaskSchedulerEngine(
            modelContext: context,
            preflightValidator: preflightValidator
        )
        let coordinator = ScheduledTaskSchedulerCoordinator(
            modelContext: context,
            engine: engine,
            rootLock: ScheduledTaskRootLock(),
            materializer: materializer,
            executor: executor,
            keepAwakeService: keepAwakeService,
            notificationManager: notificationManager,
            terminalConversationReconciliation: terminalConversationReconciliation,
            definitionFailureNotification: definitionFailureNotification,
            clearPendingOccurrence: clearPendingOccurrence,
            savePendingOccurrenceState: savePendingOccurrenceState,
            saveTerminalState: saveTerminalState,
            persistenceRetryWait: persistenceRetryWait,
            now: { actionDate.addingTimeInterval(1) }
        )
        return ScheduledTaskCoordinatorServices(
            coordinator: coordinator,
            executor: executor,
            keepAwakeService: keepAwakeService,
            notificationManager: notificationManager
        )
    }

    func runs() throws -> [ScheduledTaskRun] {
        try context.fetch(FetchDescriptor<ScheduledTaskRun>())
    }

    @discardableResult
    func insertRun(
        definition: ScheduledTask,
        status: ScheduledTaskRunStatus
    ) throws -> ScheduledTaskRun {
        let run = ScheduledTaskRun(
            snapshotting: definition,
            occurrenceID: "recovery-\(definition.id)",
            occurrenceAt: actionDate,
            triggerKind: .scheduled,
            status: status
        )
        context.insert(run)
        try context.save()
        return run
    }
}

@MainActor
final class ScheduledTaskCoordinatorMaterializer: ScheduledTaskRunMaterializing {
    private let modelContext: ModelContext
    private let probe: ScheduledTaskBlockingProbe?
    private let failureDefinitionIDs: Set<String>
    private let provenanceFailureIDs: Set<String>

    init(
        modelContext: ModelContext,
        probe: ScheduledTaskBlockingProbe?,
        failureDefinitionIDs: Set<String>,
        provenanceFailureIDs: Set<String>
    ) {
        self.modelContext = modelContext
        self.probe = probe
        self.failureDefinitionIDs = failureDefinitionIDs
        self.provenanceFailureIDs = provenanceFailureIDs
    }

    func materialize(runID: PersistentIdentifier) async throws -> ScheduledTaskRunMaterialization {
        let run = try XCTUnwrap(modelContext.resolveScheduledTaskRun(id: runID))
        let definitionID = run.definitionID
        run.status = .preparing
        run.preparationStartedAt = .now
        if provenanceFailureIDs.contains(definitionID) {
            if definitionID.hasPrefix("shell-") {
                _ = ensureTaskThread(for: run)
                try modelContext.save()
                run.status = .failure
                run.finishedAt = .now
                run.lastError = ScheduledTaskCoordinatorTestError.pendingSave.localizedDescription
            } else {
                try modelContext.save()
            }
            throw ScheduledTaskRunMaterializationError.provenancePersistenceFailed(
                ScheduledTaskCoordinatorTestError.pendingSave
            )
        }
        let (threadID, conversationID) = ensureTaskThread(for: run)
        try modelContext.save()
        if let probe {
            await probe.enter(definitionID)
            try Task.checkCancellation()
        }
        if failureDefinitionIDs.contains(definitionID) {
            throw ScheduledTaskCoordinatorTestError.materialization
        }
        let sourceRoot = run.projectPathSnapshot ?? "/tmp/private-\(definitionID)"
        let primaryRoot = run.workspaceStrategySnapshot == .worktree
            ? "/tmp/worktrees/\(definitionID)"
            : sourceRoot
        let workspace = TaskWorkspaceDescriptor(
            primaryRoot: primaryRoot,
            grantedRoots: run.grantedRootsSnapshot,
            ownershipStrategy: run.workspaceStrategySnapshot == .worktree ? .projectWorktreeOwned : .projectLocal,
            sourceProjectPath: sourceRoot
        )
        return ScheduledTaskRunMaterialization(
            runID: runID,
            threadID: threadID,
            conversationID: conversationID,
            prompt: run.promptSnapshot,
            workspace: workspace
        )
    }

    private func ensureTaskThread(
        for run: ScheduledTaskRun
    ) -> (PersistentIdentifier, String) {
        if let thread = run.thread,
           let conversation = thread.conversations.first(where: \.isMain) {
            return (thread.persistentModelID, conversation.id)
        }
        let thread = AgentThread(
            name: run.titleSnapshot,
            mode: .task,
            scheduledTaskRun: run
        )
        let conversation = Conversation(isMain: true, isUnread: false, thread: thread)
        thread.conversations = [conversation]
        run.thread = thread
        modelContext.insert(thread)
        modelContext.insert(conversation)
        return (thread.persistentModelID, conversation.id)
    }
}

@MainActor
final class ScheduledTaskCoordinatorExecutor: ScheduledTaskRunExecuting {
    private let modelContext: ModelContext
    private let probe: ScheduledTaskBlockingProbe?
    private let stopProbe: ScheduledTaskBlockingProbe?
    private let failureDefinitionIDs: Set<String>
    private(set) var stopRunIDs: [PersistentIdentifier] = []
    private var stoppedRunIDs: Set<PersistentIdentifier> = []

    init(
        modelContext: ModelContext,
        probe: ScheduledTaskBlockingProbe?,
        stopProbe: ScheduledTaskBlockingProbe?,
        failureDefinitionIDs: Set<String>
    ) {
        self.modelContext = modelContext
        self.probe = probe
        self.stopProbe = stopProbe
        self.failureDefinitionIDs = failureDefinitionIDs
    }

    func execute(_ materialization: ScheduledTaskRunMaterialization) async throws -> ScheduledTaskRunExecutionResult {
        let run = try XCTUnwrap(modelContext.resolveScheduledTaskRun(id: materialization.runID))
        let definitionID = run.definitionID
        if let probe {
            await probe.enter(definitionID)
            try Task.checkCancellation()
        }
        if failureDefinitionIDs.contains(definitionID) {
            throw ScheduledTaskCoordinatorTestError.execution
        }
        return stoppedRunIDs.contains(materialization.runID) ? .interrupted : .succeeded
    }

    func stop(runID: PersistentIdentifier) async throws {
        stopRunIDs.append(runID)
        stoppedRunIDs.insert(runID)
        if let stopProbe {
            await stopProbe.enter("stop")
        }
        await probe?.release()
    }
}

import Foundation
import SwiftData
@MainActor
final class ScheduledTaskSchedulerCoordinator {
    let modelContext: ModelContext
    private let engine: ScheduledTaskSchedulerEngine
    private let rootLock: ScheduledTaskRootLock
    private let materializer: any ScheduledTaskRunMaterializing
    private let executor: any ScheduledTaskRunExecuting
    private let keepAwakeService: any KeepAwakeService
    let notificationManager: any NotificationManager
    let terminalConversationReconciliation: TerminalConversationReconciliation
    private let definitionFailureNotification: DefinitionFailureNotification
    private let clearPendingOccurrence: PendingOccurrenceClearer
    let saveTerminalState: TerminalStateSaver
    let persistenceRetryWait: PersistenceRetryWait
    let now: @MainActor () -> Date
    private var launches: [UUID: ScheduledTaskActiveLaunch] = [:]
    var launchIDsByRunID: [PersistentIdentifier: UUID] = [:]
    var definitionsBeingClaimed: Set<String> = []
    private var definitionsBeingStopped: Set<String> = []
    private var definitionsWithDurableStopClear: Set<String> = []
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private var runIdleWaiters: [PersistentIdentifier: [CheckedContinuation<Void, Never>]] = [:]
    private var lifecycleState = ScheduledTaskCoordinatorLifecycleState.running
    var schedulingStateDidChange: SchedulingStateDidChange?

    init(
        modelContext: ModelContext,
        engine: ScheduledTaskSchedulerEngine,
        rootLock: ScheduledTaskRootLock,
        materializer: any ScheduledTaskRunMaterializing,
        executor: any ScheduledTaskRunExecuting,
        keepAwakeService: any KeepAwakeService,
        notificationManager: any NotificationManager,
        terminalConversationReconciliation: @escaping TerminalConversationReconciliation = { _ in },
        definitionFailureNotification: @escaping DefinitionFailureNotification = { _, _, _ in },
        clearPendingOccurrence: PendingOccurrenceClearer? = nil,
        savePendingOccurrenceState: PendingOccurrenceStateSaver? = nil,
        saveTerminalState: TerminalStateSaver? = nil,
        persistenceRetryWait: @escaping PersistenceRetryWait = waitForScheduledTaskCoordinatorPersistenceRetry,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.engine = engine
        self.rootLock = rootLock
        self.materializer = materializer
        self.executor = executor
        self.keepAwakeService = keepAwakeService
        self.notificationManager = notificationManager
        self.terminalConversationReconciliation = terminalConversationReconciliation
        self.definitionFailureNotification = definitionFailureNotification
        let savePendingOccurrenceState = savePendingOccurrenceState ?? { try modelContext.save() }
        self.clearPendingOccurrence = clearPendingOccurrence ?? { runID in
            guard let run = modelContext.resolveScheduledTaskRun(id: runID),
                  let definition = run.scheduledTask,
                  let pendingOccurrenceAt = definition.pendingOccurrenceAt else {
                return
            }
            let previousStateRawValue = definition.stateRawValue
            let previousTargetWaitStartedAt = definition.targetWaitStartedAt
            definition.pendingOccurrenceAt = nil
            definition.targetWaitStartedAt = nil
            if definition.recurrence?.isOneShot == true,
               definition.nextOccurrenceAt == nil {
                definition.state = .completed
            }
            do {
                try savePendingOccurrenceState()
            } catch {
                definition.pendingOccurrenceAt = pendingOccurrenceAt
                definition.targetWaitStartedAt = previousTargetWaitStartedAt
                definition.stateRawValue = previousStateRawValue
                throw error
            }
        }
        self.saveTerminalState = saveTerminalState ?? { try modelContext.save() }
        self.persistenceRetryWait = persistenceRetryWait
        self.now = now
    }

    /// Starts one independent claim pipeline for each due definition. This method does not
    /// wait for the runs to finish, allowing disjoint workspaces to execute concurrently.
    @discardableResult
    func startDueTasks(at actionDate: Date = .now) throws -> Int {
        guard lifecycleState == .running else {
            return 0
        }
        let definitions = try modelContext.fetch(FetchDescriptor<ScheduledTask>()).sorted {
            let lhsDate = $0.targetWaitStartedAt ?? $0.pendingOccurrenceAt ?? $0.nextOccurrenceAt ?? $0.createdAt
            let rhsDate = $1.targetWaitStartedAt ?? $1.pendingOccurrenceAt ?? $1.nextOccurrenceAt ?? $1.createdAt
            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }
            return $0.id < $1.id
        }
        var selectedTargetIDs = Set<PersistentIdentifier>()
        let dueDefinitionIDs = definitions.compactMap { definition -> String? in
            let persistedState = ScheduledTaskState(rawValue: definition.stateRawValue)
            guard persistedState != .completed else {
                return nil
            }
            let hasActiveRun = definition.runs.contains { !$0.hasKnownTerminalStatus }
            let nextIsDue = definition.nextOccurrenceAt.map { $0 <= actionDate } ?? false
            let pendingIsDue = !hasActiveRun && (definition.pendingOccurrenceAt.map { $0 <= actionDate } ?? false)
            let needsDefinitionValidation = persistedState == nil || (
                persistedState == .active
                    && definition.nextOccurrenceAt == nil
                    && definition.pendingOccurrenceAt == nil
            )
            guard nextIsDue || pendingIsDue || needsDefinitionValidation else {
                return nil
            }
            if definition.decodedDestination == .existingThread,
               let targetID = definition.targetThread?.persistentModelID {
                guard selectedTargetIDs.insert(targetID).inserted else {
                    return nil
                }
            }
            return definition.id
        }
        return dueDefinitionIDs.reduce(into: 0) { count, definitionID in
            if startDueTask(definitionID: definitionID, at: actionDate) {
                count += 1
            }
        }
    }

    /// Starts a due claim unless the same definition is already inside asynchronous preflight.
    /// A definition that is already executing may still be claimed so the engine can coalesce
    /// its latest overlapping occurrence.
    @discardableResult
    func startDueTask(
        definitionID: String,
        at actionDate: Date = .now
    ) -> Bool {
        startClaim(definitionID: definitionID, reportsClaimErrors: false) { [engine] in
            try await engine.claimDue(definitionID: definitionID, at: actionDate)
        }
    }

    @discardableResult
    func startRunNow(_ request: ScheduledTaskRunNowRequest) -> Bool {
        startClaim(definitionID: request.definitionID, reportsClaimErrors: true) { [engine] in
            try await engine.claimRunNow(request)
        }
    }

    /// Launches claimed runs selected by recovery after persisted state has been reconciled.
    @discardableResult
    func resumeClaimedRuns(_ runIDs: [PersistentIdentifier]) -> Int {
        guard lifecycleState == .running else {
            return 0
        }
        return runIDs.reduce(into: 0) { count, runID in
            guard launchIDsByRunID[runID] == nil,
                  let run = modelContext.resolveScheduledTaskRun(id: runID),
                  run.status == .claimed,
                  !definitionsBeingStopped.contains(run.definitionID) else {
                return
            }
            let launch = makeLaunch(definitionID: run.definitionID)
            register(runID: runID, for: launch)
            schedulingStateDidChange?(run.definitionID, nil)
            launch.task = Task { @MainActor [weak self, weak launch] in
                guard let self, let launch else {
                    return
                }
                await self.performRun(runID: runID, launch: launch)
            }
            count += 1
        }
    }

    /// Clears coalesced work for a tracked user stop, then delegates live provider cancellation
    /// to the executor. Work that has not reached the executor is cancelled locally.
    func stop(runID: PersistentIdentifier) async throws {
        guard let launchID = launchIDsByRunID[runID],
              let launch = launches[launchID],
              modelContext.resolveScheduledTaskRun(id: runID) != nil else {
            return
        }
        let definitionID = launch.definitionID
        definitionsBeingStopped.insert(definitionID)
        launch.stopRequested = true
        let siblingClaimTasks = launches.values.compactMap { sibling -> Task<Void, Never>? in
            guard sibling.id != launch.id,
                  sibling.definitionID == definitionID,
                  sibling.stage == .claiming else {
                return nil
            }
            sibling.task?.cancel()
            return sibling.task
        }

        var stopError: Error?
        if launch.stage == .executing {
            do {
                try await executor.stop(runID: runID)
            } catch {
                stopError = error
            }
        }
        if launch.stage != .executing || stopError != nil {
            launch.task?.cancel()
        }

        await clearPendingOccurrenceDurably(runID: runID)
        for siblingClaimTask in siblingClaimTasks {
            await siblingClaimTask.value
        }
        definitionsWithDurableStopClear.insert(definitionID)
        launch.markStopCompleted()
        releaseStopFenceIfPossible(definitionID: definitionID)

        if let stopError {
            throw stopError
        }
    }

    func stopAndWait(runID: PersistentIdentifier) async throws {
        if modelContext.resolveScheduledTaskRun(id: runID)?.hasKnownTerminalStatus == true {
            await waitUntilInactive(runID: runID)
            return
        }

        var stopError: Error?
        do {
            try await stop(runID: runID)
        } catch {
            stopError = error
        }
        await waitUntilInactive(runID: runID)
        if let stopError {
            throw stopError
        }
    }

    func waitUntilInactive(runID: PersistentIdentifier) async {
        while launchIDsByRunID[runID] != nil {
            await withCheckedContinuation { continuation in
                runIdleWaiters[runID, default: []].append(continuation)
            }
        }
    }

    /// Closes the launch boundary and waits for every in-flight pipeline to quiesce. Provider
    /// cancellation is owned by the executing task; user-stop semantics are intentionally not
    /// used here so coalesced occurrences remain available for the next catch-up pass.
    func beginShutdown() {
        if lifecycleState == .running {
            lifecycleState = .shuttingDown
            for launch in launches.values {
                launch.shutdownRequested = true
                launch.task?.cancel()
            }
        }
    }

    func shutdown() async {
        beginShutdown()
        await waitUntilIdle()
        lifecycleState = .shutDown
    }

    func waitUntilIdle() async {
        while !launches.isEmpty {
            await withCheckedContinuation { continuation in
                idleWaiters.append(continuation)
            }
        }
    }
}

private extension ScheduledTaskSchedulerCoordinator {
    func startClaim(
        definitionID: String,
        reportsClaimErrors: Bool,
        claim: @escaping @MainActor () async throws -> ScheduledTaskClaimResult
    ) -> Bool {
        guard lifecycleState == .running,
              !definitionsBeingStopped.contains(definitionID),
              definitionsBeingClaimed.insert(definitionID).inserted else {
            return false
        }
        let launch = makeLaunch(
            definitionID: definitionID,
            reportsClaimErrors: reportsClaimErrors
        )
        launch.task = Task { @MainActor [weak self, weak launch] in
            guard let self, let launch else {
                return
            }
            await self.performClaim(claim, launch: launch)
        }
        return true
    }

    func makeLaunch(
        definitionID: String,
        reportsClaimErrors: Bool = false
    ) -> ScheduledTaskActiveLaunch {
        let launch = ScheduledTaskActiveLaunch(
            definitionID: definitionID,
            reportsClaimErrors: reportsClaimErrors
        )
        launches[launch.id] = launch
        return launch
    }

    func performClaim(
        _ claim: @escaping @MainActor () async throws -> ScheduledTaskClaimResult,
        launch: ScheduledTaskActiveLaunch
    ) async {
        defer {
            definitionsBeingClaimed.remove(launch.definitionID)
        }
        do {
            try Task.checkCancellation()
            let result = try await claim()
            try Task.checkCancellation()
            if case let .paused(reason) = result,
               let definition = modelContext.resolveScheduledTask(id: launch.definitionID) {
                definitionFailureNotification(definition.id, definition.title, reason)
            }
            let claimErrorMessage = launch.reportsClaimErrors
                ? runNowClaimErrorMessage(for: result)
                : nil
            guard let runID = runnableRunID(from: result),
                  let run = modelContext.resolveScheduledTaskRun(id: runID),
                  run.status == .claimed else {
                finish(launch, claimErrorMessage: claimErrorMessage)
                return
            }
            if case .alreadyClaimed = result, let activeLaunchID = launchIDsByRunID[runID], launches[activeLaunchID] != nil {
                finish(launch, claimErrorMessage: claimErrorMessage)
                return
            }
            register(runID: runID, for: launch)
            definitionsBeingClaimed.remove(launch.definitionID)
            schedulingStateDidChange?(launch.definitionID, nil)
            await performRun(runID: runID, launch: launch)
        } catch is CancellationError {
            await persistInterruptedRunIfNeeded(for: launch)
            finish(
                launch,
                claimErrorMessage: launch.reportsClaimErrors
                    ? "The scheduled task Run now request was interrupted."
                    : nil
            )
        } catch {
            await persistFailedRunIfNeeded(for: launch, error: error)
            finish(
                launch,
                claimErrorMessage: launch.reportsClaimErrors ? error.localizedDescription : nil
            )
        }
    }

    func register(runID: PersistentIdentifier, for launch: ScheduledTaskActiveLaunch) {
        launch.runID = runID
        launchIDsByRunID[runID] = launch.id
    }

    func performRun(
        runID: PersistentIdentifier,
        launch: ScheduledTaskActiveLaunch
    ) async {
        let keepAwakeSource = scheduledKeepAwakeSource(runID: runID)
        if let keepAwakeSource {
            keepAwakeService.setActive(true, for: keepAwakeSource)
        }
        defer {
            if let keepAwakeSource {
                keepAwakeService.setActive(false, for: keepAwakeSource)
            }
        }
        do {
            try Task.checkCancellation()
            launch.stage = .materializing
            let materialization = try await materialize(runID: runID)
            try Task.checkCancellation()
            launch.stage = .waitingForWorkspace
            let executionResult = try await rootLock.withWorkspaceAccess(
                roots: [materialization.workspace.primaryRoot] + materialization.workspace.grantedRoots
            ) { [weak self, weak launch] in
                guard let self, let launch else {
                    throw CancellationError()
                }
                return try await self.execute(materialization, launch: launch)
            }
            await persist(executionResult, for: runID)
        } catch is CancellationError {
            await persistInterruptedRunIfNeeded(for: launch)
        } catch let materializationError as ScheduledTaskRunMaterializationError {
            switch materializationError {
            case .provenancePersistenceFailed:
                await preserveClaimedRun(
                    runID: runID,
                    error: materializationError
                )
            default:
                await persistFailedRunIfNeeded(for: launch, error: materializationError)
            }
        } catch {
            await persistFailedRunIfNeeded(for: launch, error: error)
        }
        await launch.waitForStopCompletionIfNeeded()
        let shouldStartPending = shouldStartPendingOccurrence(after: launch)
        finish(launch)
        if shouldStartPending {
            _ = startDueTask(definitionID: launch.definitionID, at: now())
        }
    }

    func materialize(runID: PersistentIdentifier) async throws -> ScheduledTaskRunMaterialization {
        guard let run = modelContext.resolveScheduledTaskRun(id: runID) else {
            throw ScheduledTaskRunMaterializationError.runMissing
        }
        let shouldLockWorktreeCreation = run.workspaceKindSnapshot == .project &&
            run.workspaceStrategySnapshot == .worktree
        let sourceProjectRoot = run.projectPathSnapshot
        if shouldLockWorktreeCreation, let sourceProjectRoot {
            return try await rootLock.withWorktreeCreationAccess(sourceProjectRoot: sourceProjectRoot) { @MainActor in
                try await self.materializer.materialize(runID: runID)
            }
        }
        return try await materializer.materialize(runID: runID)
    }

    func execute(
        _ materialization: ScheduledTaskRunMaterialization,
        launch: ScheduledTaskActiveLaunch
    ) async throws -> ScheduledTaskRunExecutionResult {
        try Task.checkCancellation()
        launch.stage = .executing
        return try await executor.execute(materialization, onUserStop: { [weak self] in
            guard let self else {
                return
            }
            try await self.stop(runID: materialization.runID)
        })
    }

    func shouldStartPendingOccurrence(after launch: ScheduledTaskActiveLaunch) -> Bool {
        guard lifecycleState == .running,
              !launch.stopRequested,
              let runID = launch.runID,
              let run = modelContext.resolveScheduledTaskRun(id: runID),
              run.hasKnownTerminalStatus,
              let definition = modelContext.resolveScheduledTask(id: launch.definitionID),
              let pendingOccurrenceAt = definition.pendingOccurrenceAt,
              pendingOccurrenceAt <= now() else {
            return false
        }
        return !definition.runs.contains { $0.persistentModelID != runID && !$0.hasKnownTerminalStatus }
    }

    func finish(
        _ launch: ScheduledTaskActiveLaunch,
        claimErrorMessage: String? = nil
    ) {
        if let runID = launch.runID,
           launchIDsByRunID[runID] == launch.id {
            launchIDsByRunID.removeValue(forKey: runID)
            let waiters = runIdleWaiters.removeValue(forKey: runID) ?? []
            waiters.forEach { $0.resume() }
        }
        definitionsBeingClaimed.remove(launch.definitionID)
        launches.removeValue(forKey: launch.id)
        releaseStopFenceIfPossible(definitionID: launch.definitionID)
        schedulingStateDidChange?(launch.definitionID, claimErrorMessage)
        guard launches.isEmpty else {
            return
        }
        let waiters = idleWaiters
        idleWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func clearPendingOccurrenceDurably(runID: PersistentIdentifier) async {
        while true {
            do {
                try clearPendingOccurrence(runID)
                return
            } catch {
                await persistenceRetryWait()
            }
        }
    }

    func releaseStopFenceIfPossible(definitionID: String) {
        guard definitionsWithDurableStopClear.contains(definitionID),
              !launches.values.contains(where: { $0.definitionID == definitionID }) else {
            return
        }
        definitionsWithDurableStopClear.remove(definitionID)
        definitionsBeingStopped.remove(definitionID)
    }
}

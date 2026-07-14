import Foundation
import SwiftData

@MainActor
final class ScheduledTaskLifecycleCoordinator {
    typealias RecoverySnapshotLoader = @MainActor () throws -> [ScheduledTaskRecoveryReadinessSnapshot]
    typealias RecoveryReadinessValidator = @MainActor @Sendable (ScheduledTaskRecoveryReadinessSnapshot) async -> Bool
    typealias RecoveryReconciler = @MainActor (
        _ actionDate: Date,
        _ safeRunIDs: Set<String>
    ) throws -> ScheduledTaskRunRecoveryResult
    typealias RecoveredRunResumer = @MainActor ([PersistentIdentifier]) -> Int
    typealias DueTaskStarter = @MainActor (Date) throws -> Int
    typealias ClaimingDefinitionLoader = @MainActor () -> Set<String>
    typealias DeadlineLoader = @MainActor (_ actionDate: Date, _ claimingDefinitionIDs: Set<String>) throws -> Date?
    typealias ShutdownBeginner = @MainActor () -> Void
    typealias TerminationPreparer = @MainActor (Date) throws -> ScheduledTaskTerminationPreparation
    typealias Sleeper = @Sendable (Duration) async throws -> Void
    typealias ErrorHandler = @MainActor (Error) -> Void
    typealias RecoveryStateChangePublisher = @MainActor () -> Void

    private let notificationCenter: NotificationCenter
    private let now: @MainActor () -> Date
    private let sleep: Sleeper
    private let loadRecoverySnapshots: RecoverySnapshotLoader
    private let validateRecoveryReadiness: RecoveryReadinessValidator
    private let recoverPersistedRuns: RecoveryReconciler
    private let resumeRecoveredRuns: RecoveredRunResumer
    private let startDueTasks: DueTaskStarter
    private let loadClaimingDefinitionIDs: ClaimingDefinitionLoader
    private let loadNextDeadline: DeadlineLoader
    private let beginSchedulerShutdown: ShutdownBeginner
    private let prepareRunsForTermination: TerminationPreparer
    private let publishRecoveryStateChange: RecoveryStateChangePublisher
    private let handleError: ErrorHandler
    private let retryDelay: TimeInterval
    private let minimumRescanDelay: TimeInterval
    private var definitionChangeObserver: NSObjectProtocol?
    private var clockChangeObserver: NSObjectProtocol?
    private var timeZoneChangeObserver: NSObjectProtocol?
    private var deadlineTask: Task<Void, Never>?
    private var deadlineGeneration = UUID()
    private var isActivated = false
    private var isTerminating = false

    private(set) var scheduledDeadline: Date?

    var canStartManualRuns: Bool {
        isActivated && !isTerminating
    }

    convenience init(
        modelContext: ModelContext,
        schedulerCoordinator: ScheduledTaskSchedulerCoordinator,
        recoveryCoordinator: ScheduledTaskRunRecoveryCoordinator,
        readinessValidator: ScheduledTaskRecoveryReadinessValidator,
        notificationCenter: NotificationCenter = .default,
        now: @escaping @MainActor () -> Date = Date.init,
        sleep: @escaping Sleeper = { try await Task.sleep(for: $0) },
        handleError: @escaping ErrorHandler = {
            print("[ScheduledTasks] Lifecycle reconciliation failed: \($0)")
        }
    ) {
        let publishSchedulerStateChange: @MainActor (String) -> Void = { definitionID in
            notificationCenter.postScheduledTasksChanged(
                definitionID: definitionID,
                schedulerClaimResolved: true
            )
        }
        self.init(
            notificationCenter: notificationCenter,
            now: now,
            sleep: sleep,
            loadRecoverySnapshots: {
                try modelContext.fetch(FetchDescriptor<ScheduledTaskRun>())
                    .filter { $0.decodedStatus == .claimed }
                    .compactMap(ScheduledTaskRecoveryReadinessSnapshot.init)
            },
            validateRecoveryReadiness: readinessValidator.isReady,
            recoverPersistedRuns: { actionDate, safeRunIDs in
                try recoveryCoordinator.recoverPersistedRuns(at: actionDate) { run in
                    safeRunIDs.contains(run.id)
                }
            },
            resumeRecoveredRuns: schedulerCoordinator.resumeClaimedRuns,
            startDueTasks: schedulerCoordinator.startDueTasks,
            loadClaimingDefinitionIDs: { schedulerCoordinator.definitionIDsBeingClaimed },
            loadNextDeadline: { actionDate, claimingDefinitionIDs in
                try Self.nextDeadline(
                    in: modelContext,
                    at: actionDate,
                    claimingDefinitionIDs: claimingDefinitionIDs
                )
            },
            beginSchedulerShutdown: schedulerCoordinator.beginShutdown,
            prepareRunsForTermination: recoveryCoordinator.prepareForTermination,
            publishRecoveryStateChange: {
                notificationCenter.postScheduledTasksChanged(object: recoveryCoordinator)
            },
            handleError: handleError
        )
        schedulerCoordinator.setSchedulingStateDidChange(publishSchedulerStateChange)
    }

    init(
        notificationCenter: NotificationCenter,
        now: @escaping @MainActor () -> Date,
        sleep: @escaping Sleeper,
        loadRecoverySnapshots: @escaping RecoverySnapshotLoader,
        validateRecoveryReadiness: @escaping RecoveryReadinessValidator,
        recoverPersistedRuns: @escaping RecoveryReconciler,
        resumeRecoveredRuns: @escaping RecoveredRunResumer,
        startDueTasks: @escaping DueTaskStarter,
        loadClaimingDefinitionIDs: @escaping ClaimingDefinitionLoader,
        loadNextDeadline: @escaping DeadlineLoader,
        beginSchedulerShutdown: @escaping ShutdownBeginner,
        prepareRunsForTermination: @escaping TerminationPreparer,
        publishRecoveryStateChange: @escaping RecoveryStateChangePublisher = {},
        retryDelay: TimeInterval = 30,
        minimumRescanDelay: TimeInterval = 1,
        handleError: @escaping ErrorHandler = { _ in }
    ) {
        self.notificationCenter = notificationCenter
        self.now = now
        self.sleep = sleep
        self.loadRecoverySnapshots = loadRecoverySnapshots
        self.validateRecoveryReadiness = validateRecoveryReadiness
        self.recoverPersistedRuns = recoverPersistedRuns
        self.resumeRecoveredRuns = resumeRecoveredRuns
        self.startDueTasks = startDueTasks
        self.loadClaimingDefinitionIDs = loadClaimingDefinitionIDs
        self.loadNextDeadline = loadNextDeadline
        self.beginSchedulerShutdown = beginSchedulerShutdown
        self.prepareRunsForTermination = prepareRunsForTermination
        self.publishRecoveryStateChange = publishRecoveryStateChange
        self.retryDelay = retryDelay
        self.minimumRescanDelay = minimumRescanDelay
        self.handleError = handleError
        installObservers()
    }

    deinit {
        MainActor.assumeIsolated {
            deadlineTask?.cancel()
            if let definitionChangeObserver {
                notificationCenter.removeObserver(definitionChangeObserver)
            }
            if let clockChangeObserver {
                notificationCenter.removeObserver(clockChangeObserver)
            }
            if let timeZoneChangeObserver {
                notificationCenter.removeObserver(timeZoneChangeObserver)
            }
        }
    }

    func activateAfterProviderRefresh() async {
        guard !isActivated, !isTerminating else {
            return
        }
        do {
            let snapshots = try loadRecoverySnapshots()
            let safeRunIDs = await safeRecoveryRunIDs(from: snapshots)
            try Task.checkCancellation()
            guard !isTerminating else {
                return
            }
            let recovery = try recoverPersistedRuns(now(), safeRunIDs)
            if !recovery.interruptedRunIDs.isEmpty {
                publishRecoveryStateChange()
            }
            _ = resumeRecoveredRuns(recovery.resumedRunIDs)
            isActivated = true
            reconcileDueTasks()
        } catch is CancellationError {
            return
        } catch {
            handleError(error)
            scheduleRetry()
        }
    }

    func reconcileAfterSystemChange() {
        guard isActivated, !isTerminating else {
            return
        }
        reconcileDueTasks()
    }

    func scheduleDefinitionsChanged() {
        guard isActivated, !isTerminating else {
            return
        }
        reconcileDueTasks()
    }

    func prepareForTermination(at actionDate: Date = .now) throws -> ScheduledTaskTerminationPreparation {
        guard !isTerminating else {
            return ScheduledTaskTerminationPreparation(
                interruptedRunIDs: [],
                conversationIDsToTerminate: [],
                controllerFlushFailures: []
            )
        }
        isTerminating = true
        cancelDeadline()
        beginSchedulerShutdown()
        return try prepareRunsForTermination(actionDate)
    }

    static func nextDeadline(
        in modelContext: ModelContext,
        at actionDate: Date,
        claimingDefinitionIDs: Set<String>
    ) throws -> Date? {
        let definitions = try modelContext.fetch(FetchDescriptor<ScheduledTask>())
        return definitions.reduce(nil as Date?) { earliest, definition in
            guard ScheduledTaskState(rawValue: definition.stateRawValue) != .completed else {
                return earliest
            }
            let hasActiveRun = definition.runs.contains { !$0.hasKnownTerminalStatus }
            var candidates = [definition.nextOccurrenceAt].compactMap { $0 }
            if !hasActiveRun, let pendingOccurrenceAt = definition.pendingOccurrenceAt {
                candidates.append(pendingOccurrenceAt)
            }
            let hasPersistedOccurrence = definition.nextOccurrenceAt != nil || definition.pendingOccurrenceAt != nil
            let needsValidation = ScheduledTaskState(rawValue: definition.stateRawValue) == nil || (
                definition.state == .active && !hasPersistedOccurrence
            )
            if needsValidation {
                candidates.append(actionDate)
            }
            if claimingDefinitionIDs.contains(definition.id) {
                candidates.removeAll { $0 <= actionDate }
            }
            guard let candidate = candidates.min() else {
                return earliest
            }
            return earliest.map { min($0, candidate) } ?? candidate
        }
    }
}

private extension ScheduledTaskLifecycleCoordinator {
    func installObservers() {
        let reconcile: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleDefinitionsChanged()
            }
        }
        definitionChangeObserver = notificationCenter.addObserver(
            forName: .scheduledTasksChanged,
            object: nil,
            queue: .main,
            using: reconcile
        )
        clockChangeObserver = notificationCenter.addObserver(
            forName: NSNotification.Name.NSSystemClockDidChange,
            object: nil,
            queue: .main,
            using: reconcile
        )
        timeZoneChangeObserver = notificationCenter.addObserver(
            forName: NSNotification.Name.NSSystemTimeZoneDidChange,
            object: nil,
            queue: .main,
            using: reconcile
        )
    }

    func safeRecoveryRunIDs(
        from snapshots: [ScheduledTaskRecoveryReadinessSnapshot]
    ) async -> Set<String> {
        var safeRunIDs = Set<String>()
        for snapshot in snapshots where await validateRecoveryReadiness(snapshot) {
            safeRunIDs.insert(snapshot.runID)
        }
        return safeRunIDs
    }

    func reconcileDueTasks() {
        do {
            _ = try startDueTasks(now())
            try rearmDeadline()
        } catch {
            handleError(error)
            scheduleRetry()
        }
    }

    func rearmDeadline() throws {
        let actionDate = now()
        let nextDeadline = try loadNextDeadline(actionDate, loadClaimingDefinitionIDs())
        guard let nextDeadline else {
            cancelDeadline()
            return
        }
        let earliestAllowedDeadline = actionDate.addingTimeInterval(minimumRescanDelay)
        scheduleDeadline(max(nextDeadline, earliestAllowedDeadline), action: .reconcile)
    }

    func scheduleRetry() {
        scheduleDeadline(
            now().addingTimeInterval(retryDelay),
            action: isActivated ? .reconcile : .activate
        )
    }

    func scheduleDeadline(_ deadline: Date, action: ScheduledTaskDeadlineAction) {
        deadlineTask?.cancel()
        scheduledDeadline = deadline
        deadlineGeneration = UUID()
        let generation = deadlineGeneration
        let delay = max(0, deadline.timeIntervalSince(now()))
        let sleep = sleep
        deadlineTask = Task { @MainActor [weak self] in
            do {
                try await sleep(.seconds(delay))
            } catch {
                return
            }
            guard let self,
                  !Task.isCancelled,
                  self.deadlineGeneration == generation,
                  !self.isTerminating else {
                return
            }
            self.deadlineTask = nil
            self.scheduledDeadline = nil
            switch action {
            case .activate:
                await self.activateAfterProviderRefresh()
            case .reconcile:
                self.reconcileDueTasks()
            }
        }
    }

    func cancelDeadline() {
        deadlineTask?.cancel()
        deadlineTask = nil
        deadlineGeneration = UUID()
        scheduledDeadline = nil
    }
}

private enum ScheduledTaskDeadlineAction: Sendable {
    case activate
    case reconcile
}

private extension ScheduledTaskRecoveryReadinessSnapshot {
    @MainActor
    init?(_ run: ScheduledTaskRun) {
        guard let workspaceKind = run.workspaceKindSnapshot,
              let workspaceStrategy = run.workspaceStrategySnapshot,
              let claimedWorkspaceIdentities = run.workspaceIdentitySnapshot else {
            return nil
        }
        runID = run.id
        preflight = ScheduledTaskPreflightSnapshot(
            definitionID: run.definitionID,
            definitionRevision: run.definitionRevision,
            scheduledOccurrenceAt: run.occurrenceAt,
            recurrence: .once(run.occurrenceAt),
            timeZoneIdentifier: run.timeZoneIdentifierSnapshot,
            providerID: run.providerIDSnapshot,
            model: run.modelSnapshot,
            effort: run.effortSnapshot,
            permissionMode: run.permissionModeSnapshot,
            workspaceKind: workspaceKind,
            workspaceStrategy: workspaceStrategy,
            projectPath: run.projectPathSnapshot,
            projectBaseRef: run.projectBaseRefSnapshot,
            projectRemoteName: run.projectRemoteNameSnapshot,
            grantedRoots: run.grantedRootsSnapshot
        )
        self.claimedWorkspaceIdentities = claimedWorkspaceIdentities
    }
}

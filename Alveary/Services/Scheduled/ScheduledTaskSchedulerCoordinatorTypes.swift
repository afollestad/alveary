import Foundation
import SwiftData

extension ScheduledTaskSchedulerCoordinator {
    typealias PendingOccurrenceClearer = @MainActor (PersistentIdentifier) throws -> Void
    typealias PendingOccurrenceStateSaver = @MainActor () throws -> Void
    typealias TerminalStateSaver = @MainActor () throws -> Void
    typealias TerminalConversationReconciliation = @MainActor (_ conversationID: String) -> Void
    typealias DefinitionFailureNotification = @MainActor (String, String, String) -> Void
    typealias PersistenceRetryWait = @MainActor () async -> Void
    typealias SchedulingStateDidChange = @MainActor (String, String?) -> Void

    var activeRunIDs: Set<PersistentIdentifier> {
        Set(launchIDsByRunID.keys)
    }

    var definitionIDsBeingClaimed: Set<String> {
        definitionsBeingClaimed
    }

    func setSchedulingStateDidChange(_ handler: @escaping SchedulingStateDidChange) {
        schedulingStateDidChange = handler
    }

    func isActive(runID: PersistentIdentifier) -> Bool {
        launchIDsByRunID[runID] != nil
    }

    func runnableRunID(from result: ScheduledTaskClaimResult) -> PersistentIdentifier? {
        switch result {
        case .claimed(let runID), .alreadyClaimed(let runID):
            return runID
        case .skipped, .overlapped, .waitingForTarget, .paused, .changedDuringPreflight,
             .activeRunExists, .inactive, .notDue, .definitionNotFound:
            return nil
        }
    }

    func runNowClaimErrorMessage(for result: ScheduledTaskClaimResult) -> String? {
        switch result {
        case .waitingForTarget:
            "This scheduled task couldn't start because its pinned target thread is busy. Try again when the thread is idle."
        case .activeRunExists:
            "This scheduled task already has a run in progress."
        case .changedDuringPreflight:
            "This scheduled task changed before Run now could start. Try again."
        case .paused(let reason):
            reason
        case .inactive:
            "This scheduled task is no longer active."
        case .definitionNotFound:
            "This scheduled task no longer exists."
        case .notDue:
            "This scheduled task could not be started now."
        case .claimed, .alreadyClaimed, .skipped, .overlapped:
            nil
        }
    }
}

enum ScheduledTaskCoordinatorLifecycleState {
    case running
    case shuttingDown
    case shutDown
}

@MainActor
final class ScheduledTaskActiveLaunch {
    enum Stage {
        case claiming
        case materializing
        case waitingForWorkspace
        case executing
    }

    let id = UUID()
    let definitionID: String
    let reportsClaimErrors: Bool
    var runID: PersistentIdentifier?
    var stage = Stage.claiming
    var stopRequested = false
    var shutdownRequested = false
    var task: Task<Void, Never>?
    private var stopCompleted = false
    private var stopCompletionWaiters: [CheckedContinuation<Void, Never>] = []

    init(definitionID: String, reportsClaimErrors: Bool) {
        self.definitionID = definitionID
        self.reportsClaimErrors = reportsClaimErrors
    }

    func waitForStopCompletionIfNeeded() async {
        guard stopRequested, !stopCompleted else {
            return
        }
        await withCheckedContinuation { continuation in
            stopCompletionWaiters.append(continuation)
        }
    }

    func markStopCompleted() {
        guard !stopCompleted else {
            return
        }
        stopCompleted = true
        let waiters = stopCompletionWaiters
        stopCompletionWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

extension ScheduledTaskSchedulerCoordinator {
    func scheduledKeepAwakeSource(runID: PersistentIdentifier) -> KeepAwakeActivitySource? {
        modelContext.resolveScheduledTaskRun(id: runID).map {
            .scheduledTaskRun(runID: $0.id)
        }
    }
}

@MainActor
func waitForScheduledTaskCoordinatorPersistenceRetry() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
            continuation.resume()
        }
    }
}

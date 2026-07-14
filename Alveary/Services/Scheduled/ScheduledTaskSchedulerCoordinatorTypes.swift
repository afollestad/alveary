import Foundation
import SwiftData

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
    var runID: PersistentIdentifier?
    var stage = Stage.claiming
    var stopRequested = false
    var shutdownRequested = false
    var task: Task<Void, Never>?
    private var stopCompleted = false
    private var stopCompletionWaiters: [CheckedContinuation<Void, Never>] = []

    init(definitionID: String) {
        self.definitionID = definitionID
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

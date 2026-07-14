import Foundation

@testable import Alveary

@MainActor
struct ScheduledTaskCoordinatorServices {
    let coordinator: ScheduledTaskSchedulerCoordinator
    let executor: ScheduledTaskCoordinatorExecutor
    let keepAwakeService: RecordingKeepAwakeService
    let notificationManager: RecordingNotificationManager
}

enum ScheduledTaskCoordinatorTestError: LocalizedError, Equatable {
    case materialization
    case execution
    case pendingSave

    var errorDescription: String? {
        switch self {
        case .materialization:
            "Materialization failed."
        case .execution:
            "Execution failed."
        case .pendingSave:
            "Pending occurrence save failed."
        }
    }
}

actor ScheduledTaskBlockingProbe {
    struct Snapshot: Sendable {
        let entryCount: Int
        let maximumConcurrentCount: Int
    }

    private var entryIDs: [String] = []
    private var activeCount = 0
    private var maximumConcurrentCount = 0
    private var availablePermits = 0
    private var permitWaiters: [CheckedContinuation<Void, Never>] = []
    private var isOpenForTeardown = false

    func enter(_ id: String) async {
        entryIDs.append(id)
        activeCount += 1
        maximumConcurrentCount = max(maximumConcurrentCount, activeCount)
        if isOpenForTeardown {
            activeCount -= 1
            return
        } else if availablePermits > 0 {
            availablePermits -= 1
        } else {
            await withCheckedContinuation { continuation in
                permitWaiters.append(continuation)
            }
        }
        activeCount -= 1
    }

    func release(count: Int = 1) {
        for _ in 0 ..< count {
            if permitWaiters.isEmpty {
                availablePermits += 1
            } else {
                permitWaiters.removeFirst().resume()
            }
        }
    }

    func releaseAllForTeardown() {
        isOpenForTeardown = true
        availablePermits = 0
        let waiters = permitWaiters
        permitWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func snapshot() -> Snapshot {
        Snapshot(entryCount: entryIDs.count, maximumConcurrentCount: maximumConcurrentCount)
    }
}

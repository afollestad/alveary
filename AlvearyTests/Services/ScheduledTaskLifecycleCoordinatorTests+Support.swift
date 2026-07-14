import Foundation

final class ScheduledLifecycleTestSleeper: @unchecked Sendable {
    private struct PendingSleep {
        let duration: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var pendingOrder: [UUID] = []
    private var pendingSleeps: [UUID: PendingSleep] = [:]

    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let shouldCancel = lock.withLock {
                    guard !Task.isCancelled else {
                        return true
                    }
                    pendingOrder.append(id)
                    pendingSleeps[id] = PendingSleep(duration: duration, continuation: continuation)
                    return false
                }
                if shouldCancel {
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            self.cancel(id: id)
        }
    }

    func pendingDurations() -> [Duration] {
        lock.withLock {
            pendingOrder.compactMap { pendingSleeps[$0]?.duration }
        }
    }

    func resumeNext() {
        let continuation: CheckedContinuation<Void, any Error>? = lock.withLock {
            while let id = pendingOrder.first {
                pendingOrder.removeFirst()
                guard let pendingSleep = pendingSleeps.removeValue(forKey: id) else {
                    continue
                }
                return pendingSleep.continuation
            }
            return nil
        }
        continuation?.resume()
    }

    private func cancel(id: UUID) {
        let continuation: CheckedContinuation<Void, any Error>? = lock.withLock {
            guard let pendingSleep = pendingSleeps.removeValue(forKey: id) else {
                return nil
            }
            pendingOrder.removeAll { $0 == id }
            return pendingSleep.continuation
        }
        continuation?.resume(throwing: CancellationError())
    }
}

@MainActor
func scheduledTaskLifecycleWaitUntil(
    _ description: String,
    timeout: Duration = .seconds(2),
    pollInterval: Duration = .milliseconds(10),
    condition: @escaping @MainActor () async -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(for: pollInterval)
    }
    throw ScheduledTaskLifecycleTestError.timeout(description)
}

enum ScheduledTaskLifecycleTestError: Error {
    case plannedFailure
    case timeout(String)
}

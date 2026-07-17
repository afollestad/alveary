import Foundation

@testable import Alveary

final class TestChatVoiceInputClock: ChatVoiceInputClock, @unchecked Sendable {
    private struct Sleeper {
        let id: UUID
        let deadline: Duration
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var current: Duration = .zero
    private var sleepers: [Sleeper] = []

    var pendingSleeperCount: Int {
        lock.withLock { sleepers.count }
    }

    func now() -> Duration {
        lock.withLock { current }
    }

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let shouldCancel = lock.withLock { () -> Bool in
                    guard !Task<Never, Never>.isCancelled else {
                        return true
                    }
                    sleepers.append(Sleeper(
                        id: id,
                        deadline: current + duration,
                        continuation: continuation
                    ))
                    return false
                }
                if shouldCancel {
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            self.cancelSleeper(id: id)
        }
    }

    func advance(by duration: Duration) {
        let ready = lock.withLock { () -> [Sleeper] in
            current += duration
            let ready = sleepers.filter { $0.deadline <= current }
            sleepers.removeAll { $0.deadline <= current }
            return ready
        }
        for sleeper in ready {
            sleeper.continuation.resume()
        }
    }

    private func cancelSleeper(id: UUID) {
        let sleeper = lock.withLock { () -> Sleeper? in
            guard let index = sleepers.firstIndex(where: { $0.id == id }) else {
                return nil
            }
            return sleepers.remove(at: index)
        }
        sleeper?.continuation.resume(throwing: CancellationError())
    }
}

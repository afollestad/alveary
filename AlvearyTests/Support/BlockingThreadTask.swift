import Dispatch
import Foundation

/// Runs `body` — synchronous work that blocks, such as `shutdownSynchronously()` against a gated
/// fake — on a user-interactive GCD thread, started immediately and awaitable through `value`.
///
/// Neither the work nor the handle touches the cooperative pool. These tests block their own
/// bodies on semaphores the work signals, and fakes such as `VoiceInputAudioCaptureFake` park a
/// pool thread on purpose; a blocked pool thread is never replaced, so work that needed one — even
/// just to start a `Task.detached` wrapper — could starve on a small CI runner until an ordering
/// assertion had already failed. Running at user-interactive keeps a main-thread wait on the work
/// from being reported as a Thread Performance Checker priority inversion, which fails
/// `scripts/test.sh`.
func blockingThreadTask<Success: Sendable>(
    _ body: @escaping @Sendable () -> Success
) -> BlockingThreadWork<Success, Never> {
    let work = BlockingThreadWork<Success, Never>()
    DispatchQueue.global(qos: .userInteractive).async {
        work.resolve(.success(body()))
    }
    return work
}

/// `blockingThreadTask(_:)` for work that throws; the error surfaces from `value`.
func throwingBlockingThreadTask<Success: Sendable>(
    _ body: @escaping @Sendable () throws -> Success
) -> BlockingThreadWork<Success, any Error> {
    let work = BlockingThreadWork<Success, any Error>()
    DispatchQueue.global(qos: .userInteractive).async {
        work.resolve(Result { try body() })
    }
    return work
}

/// The awaitable result of `blockingThreadTask(_:)`. Awaiting it resumes the caller on its own
/// executor — the main actor for most of these tests — rather than on a pool thread.
final class BlockingThreadWork<Success: Sendable, Failure: Error>: @unchecked Sendable {
    private let lock = NSLock()
    private var outcome: Result<Success, Failure>?
    private var waiters: [CheckedContinuation<Result<Success, Failure>, Never>] = []

    var value: Success {
        get async throws(Failure) {
            try await resolvedOutcome().get()
        }
    }

    fileprivate func resolve(_ outcome: Result<Success, Failure>) {
        let waiters = lock.withLock { () -> [CheckedContinuation<Result<Success, Failure>, Never>] in
            self.outcome = outcome
            defer { self.waiters = [] }
            return self.waiters
        }
        waiters.forEach { $0.resume(returning: outcome) }
    }

    private func resolvedOutcome() async -> Result<Success, Failure> {
        await withCheckedContinuation { continuation in
            let resolved = lock.withLock { () -> Result<Success, Failure>? in
                if let outcome {
                    return outcome
                }
                waiters.append(continuation)
                return nil
            }
            if let resolved {
                continuation.resume(returning: resolved)
            }
        }
    }
}

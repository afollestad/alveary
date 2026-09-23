import Dispatch

/// Runs `body` — synchronous work that blocks, such as `shutdownSynchronously()` against a gated
/// fake — on a user-interactive GCD thread, awaitable through the returned task.
///
/// Not `Task.detached`: these tests block their own bodies on semaphores the work signals, and a
/// cooperative-pool thread parked in a blocking call is never replaced, so on a small CI runner the
/// work can starve until an ordering assertion has already failed. A GCD thread is outside that
/// pool, and running at user-interactive keeps a main-thread wait on it from being reported as a
/// Thread Performance Checker priority inversion, which fails `scripts/test.sh`.
func blockingThreadTask<Success: Sendable>(_ body: @escaping @Sendable () -> Success) -> Task<Success, Never> {
    Task.detached {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                continuation.resume(returning: body())
            }
        }
    }
}

/// `blockingThreadTask(_:)` for work that throws; the error surfaces from the task's `value`.
func throwingBlockingThreadTask<Success: Sendable>(
    _ body: @escaping @Sendable () throws -> Success
) -> Task<Success, Error> {
    Task.detached {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                continuation.resume(with: Result { try body() })
            }
        }
    }
}

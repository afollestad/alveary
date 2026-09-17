import Foundation

/// Shares only overlapping reads. Each waiter cancels independently; completed results are never cached.
actor GitHubSharedReads {
    func value(key: [String], operation: @escaping @Sendable () async throws -> ShellResult) async throws -> ShellResult {
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if let id = keys[key], entries[id] != nil {
                    entries[id]?.waiters[waiterID] = continuation
                    return
                }
                let id = UUID()
                var entry = Entry(key: key, waiters: [waiterID: continuation])
                entry.task = Task {
                    let result: Result<ShellResult, Error>
                    do { result = .success(try await operation()) } catch { result = .failure(error) }
                    finish(id: id, result: result)
                }
                entries[id] = entry
                keys[key] = id
            }
        } onCancel: {
            Task { await self.cancel(waiterID: waiterID) }
        }
    }

    /// Reads crossing a mutation boundary may finish for existing waiters, but cannot acquire new ones.
    func invalidate() { keys = [:] }

    #if DEBUG
    var waiterCount: Int { entries.values.reduce(0) { $0 + $1.waiters.count } }
    #endif

    private struct Entry {
        let key: [String]
        var waiters: [UUID: CheckedContinuation<ShellResult, Error>]
        var task: Task<Void, Never>?
    }

    private var entries: [UUID: Entry] = [:]
    private var keys: [[String]: UUID] = [:]

    private func finish(id: UUID, result: Result<ShellResult, Error>) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        if keys[entry.key] == id { keys[entry.key] = nil }
        for waiter in entry.waiters.values { waiter.resume(with: result) }
    }

    private func cancel(waiterID: UUID) {
        guard let id = entries.first(where: { $0.value.waiters[waiterID] != nil })?.key,
              let waiter = entries[id]?.waiters.removeValue(forKey: waiterID) else { return }
        waiter.resume(throwing: CancellationError())
        if entries[id]?.waiters.isEmpty == true {
            entries[id]?.task?.cancel()
            finish(id: id, result: .failure(CancellationError()))
        }
    }
}

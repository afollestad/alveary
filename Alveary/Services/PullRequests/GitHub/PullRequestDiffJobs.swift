import Foundation

/// Shared preparation outlives a bounded tool wait. Each waiter has its own deadline; timing out
/// a waiter never cancels another caller's download. Only the preparation deadline cancels work.
actor PullRequestDiffJobs<Value: Sendable> {
    init(lifetime: Duration = .seconds(1_800), preparationTimeout: Duration = .seconds(600),
         now: @escaping @Sendable () -> Date = Date.init) {
        self.lifetime = lifetime
        self.preparationTimeout = preparationTimeout
        self.now = now
    }

    func start(key: String, operation: @escaping @Sendable () async throws -> Value) -> String {
        expireIdleEntries()
        if let id = keys[key], entries[id] != nil { return id }
        let id = UUID().uuidString
        var entry = Entry(key: key)
        entry.task = Task { [weak self] in
            let result: Result<Value, Error>
            do { result = .success(try await operation()) } catch { result = .failure(error) }
            await self?.finish(id: id, result: result)
        }
        entry.deadline = Task { [weak self, preparationTimeout] in
            do { try await Task.sleep(for: preparationTimeout) } catch { return }
            await self?.timeout(id: id)
        }
        entries[id] = entry
        keys[key] = id
        return id
    }

    func value(id: String, wait: Duration? = nil) async throws -> Value? {
        expireIdleEntries()
        guard let entry = entries[id] else { throw PullRequestDiffError.expired }
        if let result = entry.result {
            scheduleExpiry(id: id)
            return try result.get()
        }
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                entries[id]?.waiters[waiterID] = continuation
                if let wait {
                    entries[id]?.waitTimers[waiterID] = Task { [weak self] in
                        do { try await Task.sleep(for: wait) } catch { return }
                        await self?.endWait(id: id, waiterID: waiterID, cancelled: false)
                    }
                }
            }
        } onCancel: {
            Task { await self.endWait(id: id, waiterID: waiterID, cancelled: true) }
        }
    }

    private struct Entry {
        let key: String
        var task: Task<Void, Never>?
        var deadline: Task<Void, Never>?
        var expiry: Task<Void, Never>?
        var expiryID: UUID?
        var expiresAt: Date?
        var result: Result<Value, Error>?
        var waiters: [UUID: CheckedContinuation<Value?, Error>] = [:]
        var waitTimers: [UUID: Task<Void, Never>] = [:]
    }

    private let lifetime: Duration
    private let preparationTimeout: Duration
    private let now: @Sendable () -> Date
    private var entries: [String: Entry] = [:]
    private var keys: [String: String] = [:]

    private func finish(id: String, result: Result<Value, Error>) {
        guard var entry = entries[id], entry.result == nil else { return }
        entry.deadline?.cancel()
        entry.deadline = nil
        entry.task = nil
        entry.result = result
        let waiters = entry.waiters.values
        entry.waitTimers.values.forEach { $0.cancel() }
        entry.waitTimers = [:]
        entry.waiters = [:]
        entries[id] = entry
        // A new initial request can retry a failure, while existing cursors still receive it.
        if case .failure = result { keys[entry.key] = nil }
        for waiter in waiters { waiter.resume(with: result.map(Optional.some)) }
        scheduleExpiry(id: id)
    }

    private func timeout(id: String) {
        entries[id]?.task?.cancel()
        finish(id: id, result: .failure(PullRequestDiffError.preparationTimedOut))
    }

    private func endWait(id: String, waiterID: UUID, cancelled: Bool) {
        guard let waiter = entries[id]?.waiters.removeValue(forKey: waiterID) else { return }
        entries[id]?.waitTimers.removeValue(forKey: waiterID)?.cancel()
        if cancelled { waiter.resume(throwing: CancellationError()) } else { waiter.resume(returning: nil) }
    }

    private func scheduleExpiry(id: String) {
        entries[id]?.expiry?.cancel()
        let expiryID = UUID()
        entries[id]?.expiryID = expiryID
        entries[id]?.expiresAt = now().addingTimeInterval(Double(lifetime.components.seconds)
            + Double(lifetime.components.attoseconds) / 1e18)
        entries[id]?.expiry = Task { [weak self, lifetime] in
            do { try await Task.sleep(for: lifetime) } catch { return }
            await self?.expire(id: id, expiryID: expiryID)
        }
    }

    private func expire(id: String, expiryID: UUID) {
        guard let entry = entries[id], entry.expiryID == expiryID else { return }
        if keys[entry.key] == id { keys[entry.key] = nil }
        entries[id] = nil
    }

    private func expireIdleEntries() {
        for (id, entry) in entries where entry.expiresAt.map({ $0 <= now() }) == true {
            entry.expiry?.cancel()
            if keys[entry.key] == id { keys[entry.key] = nil }
            entries[id] = nil
        }
    }
}

import Foundation

enum ScheduledTaskRootLockError: Error, Equatable {
    case invalidRoot(String)
    case missingWorkspaceRoots
}

actor ScheduledTaskRootLock {
    private var activeAccesses: [UUID: Access] = [:]
    private var waiters: [Waiter] = []

    func withWorkspaceAccess<Result: Sendable>(
        roots: [String],
        operation: @Sendable () async throws -> Result
    ) async throws -> Result {
        return try await withAccess(
            .workspace(try canonicalRoots(roots)),
            operation: operation
        )
    }

    func withWorktreeCreationAccess<Result: Sendable>(
        sourceProjectRoot: String,
        operation: @Sendable () async throws -> Result
    ) async throws -> Result {
        guard NSString(string: sourceProjectRoot).isAbsolutePath else {
            throw ScheduledTaskRootLockError.invalidRoot(sourceProjectRoot)
        }
        return try await withAccess(
            .worktreeCreation(CanonicalPath.normalize(sourceProjectRoot)),
            operation: operation
        )
    }
}

private extension ScheduledTaskRootLock {
    enum Access: Sendable {
        case workspace([String])
        case worktreeCreation(String)

        func conflicts(with other: Access) -> Bool {
            switch (self, other) {
            case let (.workspace(lhsRoots), .workspace(rhsRoots)):
                lhsRoots.contains { lhsRoot in
                    rhsRoots.contains { rhsRoot in
                        Self.pathsOverlap(lhsRoot, rhsRoot)
                    }
                }
            case let (.worktreeCreation(lhsRoot), .worktreeCreation(rhsRoot)):
                lhsRoot == rhsRoot
            case let (.workspace(roots), .worktreeCreation(sourceRoot)),
                 let (.worktreeCreation(sourceRoot), .workspace(roots)):
                roots.contains { Self.pathsOverlap($0, sourceRoot) }
            }
        }

        private static func pathsOverlap(_ lhs: String, _ rhs: String) -> Bool {
            isSameOrDescendant(lhs, of: rhs) || isSameOrDescendant(rhs, of: lhs)
        }

        private static func isSameOrDescendant(_ candidate: String, of ancestor: String) -> Bool {
            guard candidate != ancestor else {
                return true
            }
            if ancestor == "/" {
                return candidate.hasPrefix("/")
            }
            return candidate.hasPrefix(ancestor + "/")
        }
    }

    struct Waiter {
        let id: UUID
        let access: Access
        let continuation: CheckedContinuation<Void, any Error>
    }

    func withAccess<Result: Sendable>(
        _ access: Access,
        operation: @Sendable () async throws -> Result
    ) async throws -> Result {
        let requestID = UUID()
        try await acquire(access, requestID: requestID)
        defer { release(requestID: requestID) }
        try Task.checkCancellation()
        return try await operation()
    }

    func acquire(_ access: Access, requestID: UUID) async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                enqueue(
                    Waiter(id: requestID, access: access, continuation: continuation)
                )
            }
        } onCancel: {
            Task { await self.cancel(requestID: requestID) }
        }
    }

    func enqueue(_ waiter: Waiter) {
        if canActivate(waiter.access, considering: waiters) {
            activeAccesses[waiter.id] = waiter.access
            waiter.continuation.resume()
        } else {
            waiters.append(waiter)
        }
    }

    func release(requestID: UUID) {
        activeAccesses.removeValue(forKey: requestID)
        activateEligibleWaiters()
    }

    func cancel(requestID: UUID) {
        if let waiterIndex = waiters.firstIndex(where: { $0.id == requestID }) {
            let waiter = waiters.remove(at: waiterIndex)
            waiter.continuation.resume(throwing: CancellationError())
            activateEligibleWaiters()
        }
    }

    func activateEligibleWaiters() {
        var blockedEarlierAccesses: [Access] = []
        var remainingWaiters: [Waiter] = []
        for waiter in waiters {
            if canActivate(waiter.access, considering: blockedEarlierAccesses) {
                activeAccesses[waiter.id] = waiter.access
                waiter.continuation.resume()
            } else {
                remainingWaiters.append(waiter)
                blockedEarlierAccesses.append(waiter.access)
            }
        }
        waiters = remainingWaiters
    }

    func canActivate(_ access: Access, considering earlierWaiters: [Waiter]) -> Bool {
        canActivate(access, considering: earlierWaiters.map(\.access))
    }

    func canActivate(_ access: Access, considering earlierAccesses: [Access]) -> Bool {
        !activeAccesses.values.contains(where: { access.conflicts(with: $0) }) &&
            !earlierAccesses.contains(where: { access.conflicts(with: $0) })
    }

    func canonicalRoots(_ roots: [String]) throws -> [String] {
        var seen = Set<String>()
        let canonicalRoots = try roots.map { root in
            guard NSString(string: root).isAbsolutePath else {
                throw ScheduledTaskRootLockError.invalidRoot(root)
            }
            let canonicalRoot = CanonicalPath.normalize(root)
            return canonicalRoot
        }.filter { seen.insert($0).inserted }
        guard !canonicalRoots.isEmpty else {
            throw ScheduledTaskRootLockError.missingWorkspaceRoots
        }
        return canonicalRoots
    }
}

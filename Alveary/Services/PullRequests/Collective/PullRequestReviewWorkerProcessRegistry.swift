import Darwin
import Foundation

struct PullRequestReviewWorkerProcessKey: Hashable, Sendable {
    let runID: String
    let generation: Int
    let executionID: String
}

/// Owns the provider processes that do not belong to `AgentsManager` or a runtime conversation.
final class PullRequestReviewWorkerProcessRegistry: @unchecked Sendable {
    private struct Entry {
        let key: PullRequestReviewWorkerProcessKey
        let process: Process
        let processGroupID: pid_t?
    }

    private struct State {
        var entries: [ObjectIdentifier: Entry] = [:]
        var cancelledRunIDs: Set<String> = []
        var isShuttingDown = false
    }

    private let state = LockedState(State())
    private let notificationCenter: NotificationCenter

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    var allProcessesSnapshot: [Process] {
        state.withLock { $0.entries.values.map(\.process) }
    }

    var hasLiveProcesses: Bool {
        state.withLock { $0.entries.values.contains(where: Self.isActive) }
    }

    func tracker(for key: PullRequestReviewWorkerProcessKey) -> any ShellProcessTracking {
        PullRequestReviewWorkerProcessTracker(registry: self, key: key)
    }

    func cancel(runID: String, grace: Duration = .seconds(2)) async {
        let entries = state.withLock { state -> [Entry] in
            state.cancelledRunIDs.insert(runID)
            return state.entries.values.filter { $0.key.runID == runID }
        }
        await Self.terminate(entries, grace: grace)
    }

    func terminateAll(grace: Duration = .seconds(2)) async {
        let entries = beginShutdown()
        await Self.terminate(entries, grace: grace)
    }

    /// Synchronous because AppKit's termination callback cannot suspend while children are exiting.
    func terminateAllSynchronously(grace: TimeInterval = 2) {
        let entries = beginShutdown()
        Self.requestTermination(of: entries)
        let deadline = Date().addingTimeInterval(max(0, grace))
        while entries.contains(where: Self.isActive), Date() < deadline {
            usleep(50_000)
        }
        Self.forceKill(entries)
        let killDeadline = Date().addingTimeInterval(1)
        while entries.contains(where: Self.isActive), Date() < killDeadline {
            usleep(10_000)
        }
    }

    fileprivate func register(
        _ process: Process,
        processGroupID: pid_t?,
        key: PullRequestReviewWorkerProcessKey
    ) -> Bool {
        let accepted = state.withLock { state -> Bool in
            guard !state.isShuttingDown,
                  !state.cancelledRunIDs.contains(key.runID) else {
                return false
            }
            state.entries[ObjectIdentifier(process)] = Entry(
                key: key,
                process: process,
                processGroupID: processGroupID
            )
            return true
        }
        if accepted {
            announceChange()
        }
        return accepted
    }

    fileprivate func unregister(_ process: Process) {
        let removed = state.withLock { state in
            state.entries.removeValue(forKey: ObjectIdentifier(process)) != nil
        }
        if removed {
            announceChange()
        }
    }

    private func beginShutdown() -> [Entry] {
        let entries = state.withLock { state -> [Entry] in
            state.isShuttingDown = true
            return Array(state.entries.values)
        }
        if !entries.isEmpty {
            announceChange()
        }
        return entries
    }

    private func announceChange() {
        notificationCenter.post(name: .pullRequestReviewWorkerProcessesChanged, object: self)
    }

    private static func terminate(_ entries: [Entry], grace: Duration) async {
        requestTermination(of: entries)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: grace)
        while entries.contains(where: isActive), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        forceKill(entries)
    }

    private static func requestTermination(of entries: [Entry]) {
        for entry in entries {
            if let processGroupID = entry.processGroupID {
                if Darwin.kill(-processGroupID, SIGTERM) != 0, entry.process.isRunning {
                    entry.process.terminate()
                }
            } else if entry.process.isRunning {
                entry.process.terminate()
            }
        }
    }

    private static func forceKill(_ entries: [Entry]) {
        for entry in entries where isActive(entry) {
            if let processGroupID = entry.processGroupID {
                if Darwin.kill(-processGroupID, SIGKILL) != 0, entry.process.isRunning {
                    _ = Darwin.kill(entry.process.processIdentifier, SIGKILL)
                }
            } else if entry.process.isRunning {
                _ = Darwin.kill(entry.process.processIdentifier, SIGKILL)
            }
        }
    }

    private static func isActive(_ entry: Entry) -> Bool {
        guard let processGroupID = entry.processGroupID else {
            return entry.process.isRunning
        }
        return entry.process.isRunning || Darwin.kill(-processGroupID, 0) == 0 || errno == EPERM
    }
}

private struct PullRequestReviewWorkerProcessTracker: ShellProcessTracking {
    let registry: PullRequestReviewWorkerProcessRegistry
    let key: PullRequestReviewWorkerProcessKey

    func register(_ process: Process, processGroupID: Int32?) -> Bool {
        registry.register(process, processGroupID: processGroupID, key: key)
    }

    func unregister(_ process: Process) {
        registry.unregister(process)
    }
}

extension Notification.Name {
    static let pullRequestReviewWorkerProcessesChanged = Notification.Name(
        "pullRequestReviewWorkerProcessesChanged"
    )
}

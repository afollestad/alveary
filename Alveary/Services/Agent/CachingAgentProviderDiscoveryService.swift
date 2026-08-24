import AgentCLIKit
import Foundation

/// Memoizes the one provider-status read every thread-creation path makes.
///
/// `DefaultAgentProviderDiscoveryService.providerStatuses` spawns subprocesses per provider —
/// `which`, a login shell when that misses, `--version`, and for Codex an app-server JSON-RPC
/// session — and nothing cached the result, so creating a thread paid the whole fan-out before
/// its row could exist.
///
/// Only the `projectURL == nil` shape is cached, which is what `ThreadDefaultResolver` asks for.
/// A project-scoped read carries that project's trust state and must never be served stale, and
/// the two filtered accessors have no callers here, so all of them pass straight through.
///
/// `timeToLive` bounds *staleness*, not latency: an aged snapshot is returned on the caller's own
/// cycle and refreshed behind the answer. A TTL that instead made the read block turned every New
/// Thread click past the session's first minute back into the full fan-out, with no UI feedback
/// because selection only moves once `SidebarViewModel.openDraftThread` returns. The one read that
/// still blocks is the first after launch or after `invalidate()`, which is what the `warm()` call
/// sites front-run.
///
/// Provider *enablement* is not cached at all: `ThreadDefaultResolver` reads it from `AppSettings`
/// on every resolve. What ages here is installation state, setup readiness, and model catalogs —
/// all of which change from the Agents settings screen, which invalidates before it reads.
actor CachingAgentProviderDiscoveryService: AgentProviderDiscoveryService {
    private let base: any AgentProviderDiscoveryService
    private let timeToLive: TimeInterval
    private let now: @Sendable () -> Date

    /// One optional rather than a statuses/timestamp pair, so "have an answer" and "know its age"
    /// cannot disagree — every read decides whether to serve or refresh from both at once.
    private var snapshot: Snapshot?
    /// Every caller waiting on a probe shares this one; without it a burst of thread creations
    /// each spawns the full subprocess fan-out.
    private var inFlight: Task<[AgentProviderID: AgentProviderStatus], Never>?
    /// Bumped by `invalidate()` so a probe that started before the invalidation cannot store its
    /// now-outdated answer.
    private var generation = 0

    init(
        base: any AgentProviderDiscoveryService,
        timeToLive: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.base = base
        self.timeToLive = timeToLive
        self.now = now
    }

    func providerStatuses(projectURL: URL?) async -> [AgentProviderID: AgentProviderStatus] {
        guard projectURL == nil else {
            return await base.providerStatuses(projectURL: projectURL)
        }
        guard let snapshot else {
            return await probe().value
        }
        if !isSnapshotFresh {
            // Refresh behind the answer rather than ahead of it. Discarding the task is the
            // point: `probe()` has already published it as `inFlight`, and awaiting it here is
            // exactly the blocking read this decorator exists to prevent.
            _ = probe()
        }
        return snapshot.statuses
    }

    func installedProviderStatuses(projectURL: URL?) async -> [AgentProviderID: AgentProviderStatus] {
        await base.installedProviderStatuses(projectURL: projectURL)
    }

    func availableProviderStatuses(projectURL: URL?) async -> [AgentProviderID: AgentProviderStatus] {
        await base.availableProviderStatuses(projectURL: projectURL)
    }

    func modelOptions(for providerId: AgentProviderID) async -> [AgentModelOption] {
        await base.modelOptions(for: providerId)
    }

    func stableProviderOrdering() async -> [AgentProviderID] {
        await base.stableProviderOrdering()
    }

    /// Drops the cache and disowns any probe already running, so the next read re-probes.
    func invalidate() {
        snapshot = nil
        inFlight = nil
        generation &+= 1
    }

    /// Blocks until the snapshot is fresh, unlike `providerStatuses(projectURL:)`, which never
    /// waits once it has any snapshot at all. Launch, wake, and each opened pull request call this
    /// so the session's one genuinely blocking read happens off the click path.
    func warm() async {
        guard !isSnapshotFresh else { return }
        _ = await probe().value
    }

    /// Returns the shared probe, starting one when none is running.
    ///
    /// The result is stored from inside the task rather than by the awaiting caller, because a
    /// stale-serving read has no caller left to write it back. It must stay an unstructured
    /// `Task` for the same reason: `async let` or a task-group child would be cancelled the
    /// moment the click returns, so the refresh would never land.
    private func probe() -> Task<[AgentProviderID: AgentProviderStatus], Never> {
        if let inFlight {
            return inFlight
        }
        let startedAt = generation
        let task = Task { [self] in
            let statuses = await base.providerStatuses(projectURL: nil)
            store(statuses, generation: startedAt)
            return statuses
        }
        inFlight = task
        return task
    }

    /// Adopts a completed probe's answer unless it was invalidated mid-flight, in which case the
    /// answer predates whatever changed and `inFlight` already belongs to whoever came after.
    private func store(_ statuses: [AgentProviderID: AgentProviderStatus], generation startedAt: Int) {
        guard generation == startedAt else { return }
        inFlight = nil
        snapshot = Snapshot(statuses: statuses, storedAt: now())
    }

    private var isSnapshotFresh: Bool {
        guard let snapshot else { return false }
        return now().timeIntervalSince(snapshot.storedAt) <= timeToLive
    }

    private struct Snapshot {
        let statuses: [AgentProviderID: AgentProviderStatus]
        let storedAt: Date
    }
}

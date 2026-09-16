import AgentCLIKit
import Foundation

/// Memoizes the one harness-status read every thread-creation path makes.
///
/// `DefaultAgentHarnessDiscoveryService.harnessStatuses` spawns subprocesses per harness —
/// `which`, a login shell when that misses, `--version`, and for Codex an app-server JSON-RPC
/// session — and nothing cached the result, so creating a thread paid the whole fan-out before
/// its row could exist.
///
/// Only global metadata is cached. A project-aware decorator can reuse that metadata while
/// refreshing trust and applying its own catalog scope; other project reads pass through.
///
/// For global UI reads, `timeToLive` bounds *staleness*, not latency: an aged snapshot is returned on the caller's own
/// cycle and refreshed behind the answer. A TTL that instead made the read block turned every New
/// Thread click past the session's first minute back into the full fan-out, with no UI feedback
/// because selection only moves once `SidebarViewModel.openDraftThread` returns. The one read that
/// still blocks is the first after launch or after `invalidate()`, which is what the `warm()` call
/// sites front-run. Project reads wait for fresh global metadata because they also gate execution.
///
/// Status snapshots retain harness enablement alongside installation, setup readiness, and model catalogs.
/// `ThreadDefaultResolver` checks current `AppSettings`; strict review-team resolution refreshes the snapshot
/// when enablement changes. Harnesses settings invalidates before reading after setup changes.
actor CachingAgentHarnessDiscoveryService: AgentHarnessDiscoveryService {
    private let base: any AgentHarnessDiscoveryService
    private let timeToLive: TimeInterval
    private let now: @Sendable () -> Date

    /// One optional rather than a statuses/timestamp pair, so "have an answer" and "know its age"
    /// cannot disagree — every read decides whether to serve or refresh from both at once.
    private var snapshot: Snapshot?
    /// Every caller waiting on a probe shares this one; without it a burst of thread creations
    /// each spawns the full subprocess fan-out.
    private var inFlight: Task<[AgentHarnessID: AgentHarnessStatus], Never>?
    /// Probes must wait until configuration-dependent caches are cleared, including during actor hops.
    private var scopedInvalidation: Task<Void, Never>?
    /// Bumped when a probe is disowned so its late answer cannot replace a newer snapshot or clear its task.
    private var generation = 0

    init(
        base: any AgentHarnessDiscoveryService,
        timeToLive: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.base = base
        self.timeToLive = timeToLive
        self.now = now
    }

    func harnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] {
        if let projectURL {
            if let scoped = base as? any AgentHarnessProjectScopeApplying {
                while true {
                    let readGeneration = generation
                    let statuses = await freshGlobalStatuses()
                    let result = await scoped.applyingProjectScope(to: statuses, projectURL: projectURL)
                    if generation == readGeneration { return result }
                }
            }
            return await base.harnessStatuses(projectURL: projectURL)
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

    func installedHarnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] {
        await harnessStatuses(projectURL: projectURL).filter { $0.value.isInstalled }
    }

    func availableHarnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] {
        await harnessStatuses(projectURL: projectURL).filter { $0.value.isEnabled && $0.value.installation != .missing }
    }

    func modelOptions(for harnessId: AgentHarnessID) async -> [AgentModelOption] {
        await base.modelOptions(for: harnessId)
    }

    func stableHarnessOrdering() async -> [AgentHarnessID] {
        await base.stableHarnessOrdering()
    }

    /// Drops the cache and disowns any probe already running, so the next read re-probes.
    func invalidate() async {
        snapshot = nil
        inFlight = nil
        generation &+= 1
        await beginScopedInvalidation().value
    }

    /// Explicit repair must escape a stalled shared probe without making ordinary reads lose their last answer.
    func refresh() async {
        let superseded = inFlight
        inFlight = nil
        generation &+= 1
        superseded?.cancel()
        _ = beginScopedInvalidation()
        var awaitedGeneration = generation
        _ = await probe().value
        // Another window may supersede this refresh. Join its probe instead of letting this caller
        // validate against the preserved snapshot or force yet another replacement.
        while generation != awaitedGeneration {
            awaitedGeneration = generation
            guard inFlight != nil || snapshot == nil else { return }
            _ = await probe().value
        }
    }

    /// Blocks until the snapshot is fresh, unlike global `harnessStatuses(projectURL: nil)` reads, which never
    /// wait once they have any snapshot at all. Launch, wake, and each opened pull request call this
    /// so the session's one genuinely blocking read happens off the click path.
    func warm() async {
        guard !isSnapshotFresh else { return }
        _ = await probe().value
    }

    /// Project reads gate execution as well as presentation: expired metadata must finish refreshing,
    /// and an explicit repair already in progress must finish before its old snapshot is reused.
    private func freshGlobalStatuses() async -> [AgentHarnessID: AgentHarnessStatus] {
        while true {
            let readGeneration = generation
            let statuses: [AgentHarnessID: AgentHarnessStatus]
            if let inFlight {
                statuses = await inFlight.value
            } else if isSnapshotFresh, let snapshot {
                return snapshot.statuses
            } else {
                statuses = await probe().value
            }
            if generation == readGeneration { return statuses }
        }
    }

    /// Returns the shared probe, starting one when none is running.
    ///
    /// The result is stored from inside the task rather than by the awaiting caller, because a
    /// stale-serving read has no caller left to write it back. It must stay an unstructured
    /// `Task` for the same reason: `async let` or a task-group child would be cancelled the
    /// moment the click returns, so the refresh would never land.
    private func probe() -> Task<[AgentHarnessID: AgentHarnessStatus], Never> {
        if let inFlight {
            return inFlight
        }
        let startedAt = generation
        let task = Task { [self, scopedInvalidation] in
            await scopedInvalidation?.value
            let statuses = await base.harnessStatuses(projectURL: nil)
            store(statuses, generation: startedAt)
            return statuses
        }
        inFlight = task
        return task
    }

    /// Publish the fence before yielding, so project reads cannot bypass an explicit repair's actor hop.
    private func beginScopedInvalidation() -> Task<Void, Never> {
        let task = Task { [base, scopedInvalidation] in
            await scopedInvalidation?.value
            await (base as? any AgentHarnessDiscoveryCacheInvalidating)?.invalidateDiscoveryCaches()
        }
        scopedInvalidation = task
        return task
    }

    /// A superseded probe still answers its own caller, but must not replace the snapshot or clear the newer probe.
    private func store(_ statuses: [AgentHarnessID: AgentHarnessStatus], generation startedAt: Int) {
        guard generation == startedAt else { return }
        inFlight = nil
        snapshot = Snapshot(statuses: statuses, storedAt: now())
    }

    private var isSnapshotFresh: Bool {
        guard let snapshot else { return false }
        return now().timeIntervalSince(snapshot.storedAt) <= timeToLive
    }

    private struct Snapshot {
        let statuses: [AgentHarnessID: AgentHarnessStatus]
        let storedAt: Date
    }
}

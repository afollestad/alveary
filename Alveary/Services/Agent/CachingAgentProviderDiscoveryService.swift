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
/// Provider *enablement* is not cached at all: `ThreadDefaultResolver` reads it from `AppSettings`
/// on every resolve. What ages here is installation state, setup readiness, and model catalogs —
/// all of which change from the Agents settings screen, which invalidates before it reads.
actor CachingAgentProviderDiscoveryService: AgentProviderDiscoveryService {
    private let base: any AgentProviderDiscoveryService
    private let timeToLive: TimeInterval
    private let now: @Sendable () -> Date

    private var cachedStatuses: [AgentProviderID: AgentProviderStatus]?
    private var cachedAt: Date?
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
        if let cachedStatuses, let cachedAt, now().timeIntervalSince(cachedAt) <= timeToLive {
            return cachedStatuses
        }
        if let inFlight {
            return await inFlight.value
        }

        let startedAt = generation
        let task = Task { [base] in await base.providerStatuses(projectURL: nil) }
        inFlight = task
        let statuses = await task.value
        guard generation == startedAt else {
            // Invalidated mid-probe. The answer predates whatever changed, so it is not
            // cacheable — but it is still exactly what this caller would have got, and
            // `inFlight` now belongs to whoever came after the invalidation.
            return statuses
        }
        inFlight = nil
        cachedStatuses = statuses
        cachedAt = now()
        return statuses
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
        cachedStatuses = nil
        cachedAt = nil
        inFlight = nil
        generation &+= 1
    }

    /// Fills the cache ahead of the first thread creation. Launch calls this so the session's
    /// first New Thread or agentic review does not pay for discovery.
    func warm() async {
        _ = await providerStatuses(projectURL: nil)
    }
}

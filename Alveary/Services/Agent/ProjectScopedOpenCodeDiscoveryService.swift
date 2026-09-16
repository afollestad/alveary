import AgentCLIKit
import Foundation

/// Lets the outer discovery cache invalidate configuration-dependent snapshots held by a decorator.
protocol AgentHarnessDiscoveryCacheInvalidating: Sendable {
    func invalidateDiscoveryCaches() async
}

/// Applies live project state to reusable installation and model metadata without repeating global probes.
protocol AgentHarnessProjectScopeApplying: Sendable {
    func applyingProjectScope(
        to statuses: [AgentHarnessID: AgentHarnessStatus], projectURL: URL
    ) async -> [AgentHarnessID: AgentHarnessStatus]
}

/// OpenCode resolves providers and model variants from its working directory. Keep project catalogs
/// separate from global defaults, and replace readiness and diagnostics from that same native probe.
actor ProjectScopedOpenCodeDiscoveryService: AgentHarnessDiscoveryService, AgentHarnessDiscoveryCacheInvalidating {
    typealias Probe = @Sendable (URL) async -> OpenCodeDiscoverySnapshot

    private let base: any AgentHarnessDiscoveryService
    private let projectTrustService: any AgentProjectTrustService
    private let probe: Probe
    private let timeToLive: TimeInterval
    private let maximumCachedProjects: Int
    private let now: @Sendable () -> Date
    private var snapshots: [URL: Snapshot] = [:]
    private var inFlight: [URL: PendingProbe] = [:]
    private var accessCounter = 0

    init(
        base: any AgentHarnessDiscoveryService,
        projectTrustService: any AgentProjectTrustService,
        timeToLive: TimeInterval = 60,
        maximumCachedProjects: Int = 16,
        now: @escaping @Sendable () -> Date = Date.init,
        probe: @escaping Probe
    ) {
        self.base = base
        self.projectTrustService = projectTrustService
        self.probe = probe
        self.timeToLive = timeToLive
        self.maximumCachedProjects = max(1, maximumCachedProjects)
        self.now = now
    }

    func harnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] {
        let statuses = await base.harnessStatuses(projectURL: nil)
        guard let projectURL else { return statuses }
        return await applyingProjectScope(to: statuses, projectURL: projectURL)
    }

    func applyingProjectScope(
        to globalStatuses: [AgentHarnessID: AgentHarnessStatus], projectURL: URL
    ) async -> [AgentHarnessID: AgentHarnessStatus] {
        async let trustedStatuses = applyingProjectTrust(to: globalStatuses, projectURL: projectURL)
        guard let existing = globalStatuses[.opencode], existing.isEnabled, existing.installation != .missing else {
            return await trustedStatuses
        }
        let directory = URL(fileURLWithPath: CanonicalPath.normalize(projectURL.path), isDirectory: true)
        let snapshot = await projectSnapshot(for: directory)
        var statuses = await trustedStatuses
        var diagnostics = snapshot.diagnostics
        if existing.availability?.isAvailable == false {
            diagnostics.insert("No OpenCode executable was found.", at: 0)
        }
        statuses[.opencode] = AgentHarnessStatus(
            harnessId: .opencode,
            definition: existing.definition,
            installation: existing.installation,
            availability: existing.availability,
            isEnabled: existing.isEnabled,
            setup: snapshot.readiness,
            projectTrust: statuses[.opencode]?.projectTrust,
            modelOptions: AgentDefaultModelOptions.staticOptions(for: .opencode) + snapshot.models,
            diagnostics: diagnostics
        )
        return statuses
    }

    private func applyingProjectTrust(
        to statuses: [AgentHarnessID: AgentHarnessStatus], projectURL: URL
    ) async -> [AgentHarnessID: AgentHarnessStatus] {
        await withTaskGroup(of: AgentHarnessStatus.self, returning: [AgentHarnessID: AgentHarnessStatus].self) { group in
            for status in statuses.values {
                group.addTask { [projectTrustService] in
                    AgentHarnessStatus(
                        harnessId: status.harnessId, definition: status.definition, installation: status.installation,
                        availability: status.availability, isEnabled: status.isEnabled, setup: status.setup,
                        projectTrust: await projectTrustService.status(harnessId: status.harnessId, projectURL: projectURL),
                        modelOptions: status.modelOptions, diagnostics: status.diagnostics
                    )
                }
            }
            var scoped: [AgentHarnessID: AgentHarnessStatus] = [:]
            for await status in group { scoped[status.harnessId] = status }
            return scoped
        }
    }

    func installedHarnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] {
        await harnessStatuses(projectURL: projectURL).filter { $0.value.isInstalled }
    }

    func availableHarnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] {
        await harnessStatuses(projectURL: projectURL).filter { $0.value.isEnabled && $0.value.installation != .missing }
    }

    /// The protocol's unscoped model accessor remains the global catalog; project callers use their status snapshot.
    func modelOptions(for harnessId: AgentHarnessID) async -> [AgentModelOption] {
        await base.modelOptions(for: harnessId)
    }

    func stableHarnessOrdering() async -> [AgentHarnessID] {
        await base.stableHarnessOrdering()
    }

    func invalidateDiscoveryCaches() {
        snapshots.removeAll()
        // Older probes still answer their callers, but their identities no longer own a cache entry.
        inFlight.removeAll()
    }

    private func projectSnapshot(for directory: URL) async -> OpenCodeDiscoverySnapshot {
        accessCounter &+= 1
        if var snapshot = snapshots[directory], now().timeIntervalSince(snapshot.storedAt) <= timeToLive {
            snapshot.lastAccess = accessCounter
            snapshots[directory] = snapshot
            return snapshot.value
        }
        if let pending = inFlight[directory] { return await pending.task.value }
        let identity = UUID()
        let task = Task { await probe(directory) }
        inFlight[directory] = PendingProbe(identity: identity, task: task)
        let value = await task.value
        guard inFlight[directory]?.identity == identity else { return value }
        inFlight.removeValue(forKey: directory)
        accessCounter &+= 1
        snapshots[directory] = Snapshot(value: value, storedAt: now(), lastAccess: accessCounter)
        while snapshots.count > maximumCachedProjects,
              let oldest = snapshots.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
            snapshots.removeValue(forKey: oldest)
        }
        return value
    }
}

extension ProjectScopedOpenCodeDiscoveryService: AgentHarnessProjectScopeApplying {}

private extension ProjectScopedOpenCodeDiscoveryService {
    struct Snapshot {
        let value: OpenCodeDiscoverySnapshot
        let storedAt: Date
        var lastAccess: Int
    }

    struct PendingProbe {
        let identity: UUID
        let task: Task<OpenCodeDiscoverySnapshot, Never>
    }
}

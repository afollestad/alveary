import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

final class OpenCodeProjectDiscoveryTests: XCTestCase {
    func testProjectModelsAndReadinessReplaceGlobalSnapshotTogether() async {
        let probe = ScopedOpenCodeProbeRecorder()
        let service = ProjectScopedOpenCodeDiscoveryService(
            base: ScopedDiscoveryBase(), projectTrustService: DefaultAgentProjectTrustService(), probe: { await probe.run($0) }
        )
        let project = URL(fileURLWithPath: "/workspace/scoped-opencode")
        let scoped = await service.harnessStatuses(projectURL: project)
        let global = await service.harnessStatuses(projectURL: nil)
        let models = await service.modelOptions(for: .opencode)

        XCTAssertEqual(scoped[.opencode]?.setup, .ready)
        XCTAssertEqual(scoped[.opencode]?.modelOptions.last?.id, "local/scoped-opencode")
        XCTAssertEqual(scoped[.opencode]?.diagnostics, [])
        XCTAssertEqual(scoped[.opencode]?.projectTrust, .notRequired)
        XCTAssertEqual(scoped[.opencode]?.isReadyInProject, true)
        XCTAssertEqual(scoped[.claude]?.setup, global[.claude]?.setup)
        XCTAssertEqual(scoped[.claude]?.projectTrust, .notRequired)
        XCTAssertEqual(global[.opencode]?.setup, .needsSetup)
        XCTAssertEqual(global[.opencode]?.diagnostics, ["Global credentials missing"])
        XCTAssertEqual(models.map(\.id), ["global/model"])
        let paths = await probe.paths
        XCTAssertEqual(paths, [project.path])
    }

    func testProjectFailuresDoNotReuseAnotherProjectsModels() async {
        let probe = ScopedOpenCodeProbeRecorder()
        let service = ProjectScopedOpenCodeDiscoveryService(
            base: ScopedDiscoveryBase(), projectTrustService: DefaultAgentProjectTrustService(), probe: { await probe.run($0) }
        )
        _ = await service.harnessStatuses(projectURL: URL(fileURLWithPath: "/workspace/ready"))
        let statuses = await service.installedHarnessStatuses(projectURL: URL(fileURLWithPath: "/workspace/broken"))

        XCTAssertEqual(statuses[.opencode]?.setup, .failed)
        XCTAssertEqual(statuses[.opencode]?.modelOptions, AgentDefaultModelOptions.staticOptions(for: .opencode))
        XCTAssertEqual(statuses[.opencode]?.diagnostics, ["Project configuration failed"])
        XCTAssertEqual(statuses[.opencode]?.isReadyInProject, false)
    }

    func testConcurrentProjectReadsShareProbeAndOuterInvalidationReprobes() async {
        let probe = ScopedOpenCodeProbeRecorder()
        await probe.hold()
        let scoped = ProjectScopedOpenCodeDiscoveryService(
            base: ScopedDiscoveryBase(), projectTrustService: DefaultAgentProjectTrustService(), probe: { await probe.run($0) }
        )
        let service = CachingAgentHarnessDiscoveryService(base: scoped)
        let project = URL(fileURLWithPath: "/workspace/shared")
        async let first = service.harnessStatuses(projectURL: project)
        async let second = service.harnessStatuses(projectURL: project)
        try? await Task.sleep(for: .milliseconds(50))
        await probe.release()
        _ = await (first, second)
        let coalescedPaths = await probe.paths
        XCTAssertEqual(coalescedPaths, [project.path])

        _ = await service.harnessStatuses(projectURL: project)
        await service.invalidate()
        _ = await service.harnessStatuses(projectURL: project)
        let refreshedPaths = await probe.paths
        XCTAssertEqual(refreshedPaths, [project.path, project.path])
    }

    func testProjectCacheExpiresAndEvictsLeastRecentlyUsedEntries() async {
        let probe = ScopedOpenCodeProbeRecorder()
        let clock = ScopedDiscoveryClock()
        let service = ProjectScopedOpenCodeDiscoveryService(
            base: ScopedDiscoveryBase(), projectTrustService: DefaultAgentProjectTrustService(),
            timeToLive: 60, maximumCachedProjects: 2, now: { clock.now },
            probe: { await probe.run($0) }
        )
        for path in ["a", "b", "a", "c", "b"] {
            _ = await service.harnessStatuses(projectURL: URL(fileURLWithPath: "/workspace/\(path)"))
        }
        let paths = await probe.paths
        XCTAssertEqual(paths, ["/workspace/a", "/workspace/b", "/workspace/c", "/workspace/b"])
        clock.advance(61)
        _ = await service.availableHarnessStatuses(projectURL: URL(fileURLWithPath: "/workspace/b"))
        let expiredPaths = await probe.paths
        XCTAssertEqual(expiredPaths.last, "/workspace/b")
        XCTAssertEqual(expiredPaths.count, 5)
    }

    func testProjectReadsReuseGlobalMetadataButRefreshTrustAndKeepCatalogsScoped() async {
        let base = ScopedDiscoveryBase()
        let trust = ScopedTrustRecorder()
        let probe = ScopedOpenCodeProbeRecorder()
        let service = CachingAgentHarnessDiscoveryService(base: ProjectScopedOpenCodeDiscoveryService(
            base: base, projectTrustService: trust, probe: { await probe.run($0) }
        ))
        let firstURL = URL(fileURLWithPath: "/workspace/first")
        let secondURL = URL(fileURLWithPath: "/workspace/second")
        await service.warm()
        let first = await service.harnessStatuses(projectURL: firstURL)
        await trust.setTrust(.trusted)
        let trusted = await service.installedHarnessStatuses(projectURL: firstURL)
        let second = await service.availableHarnessStatuses(projectURL: secondURL)
        let calls = await base.projectURLs
        let paths = await probe.paths

        XCTAssertEqual(calls.count, 1)
        XCTAssertNil(calls.first.flatMap { $0 })
        XCTAssertEqual(first[.claude]?.projectTrust, .notTrusted)
        XCTAssertEqual(trusted[.claude]?.projectTrust, .trusted)
        XCTAssertEqual(second[.claude]?.projectTrust, .trusted)
        XCTAssertEqual(first[.opencode]?.modelOptions.last?.id, "local/first")
        XCTAssertEqual(second[.opencode]?.modelOptions.last?.id, "local/second")
        XCTAssertEqual(first[.opencode]?.setup, .ready)
        XCTAssertEqual(paths, [firstURL.path, secondURL.path])
    }

    func testExpiredProjectMetadataWaitsForTheCoalescedRefresh() async {
        let base = ScopedDiscoveryBase()
        let clock = ScopedDiscoveryClock()
        let probe = ScopedOpenCodeProbeRecorder()
        let service = CachingAgentHarnessDiscoveryService(
            base: ProjectScopedOpenCodeDiscoveryService(
                base: base, projectTrustService: DefaultAgentProjectTrustService(), probe: { await probe.run($0) }
            ), now: { clock.now }
        )
        let project = URL(fileURLWithPath: "/workspace/project")
        _ = await service.harnessStatuses(projectURL: project)
        clock.advance(61)
        await base.setVersion("refreshed")
        await base.hold()
        let first = Task { await service.harnessStatuses(projectURL: project) }
        await base.waitForCalls(2)
        let second = Task { await service.harnessStatuses(projectURL: project) }
        await base.release()
        let firstStatuses = await first.value
        let secondStatuses = await second.value
        let calls = await base.projectURLs

        XCTAssertEqual(firstStatuses[.opencode]?.availability?.versionDescription, "refreshed")
        XCTAssertEqual(secondStatuses[.opencode]?.availability?.versionDescription, "refreshed")
        XCTAssertEqual(calls.count, 2)
    }

    func testProjectReadRejectsMetadataFromAProbeInvalidatedDuringDiscovery() async {
        let base = ScopedDiscoveryBase()
        let service = CachingAgentHarnessDiscoveryService(base: ProjectScopedOpenCodeDiscoveryService(
            base: base, projectTrustService: DefaultAgentProjectTrustService(), probe: { _ in
                OpenCodeDiscoverySnapshot(version: "1.18.31", models: [], readiness: .ready)
            }
        ))
        await base.hold()
        let first = Task { await service.harnessStatuses(projectURL: URL(fileURLWithPath: "/workspace/project")) }
        await base.waitForCalls(1)
        await service.invalidate()
        await base.setVersion("replacement")
        let replacement = Task { await service.warm() }
        await base.waitForCalls(2)
        await base.release(call: 2)
        await replacement.value
        await base.release()
        let statuses = await first.value

        XCTAssertEqual(statuses[.opencode]?.availability?.versionDescription, "replacement")
    }

    func testExplicitRefreshReprobesGlobalMetadataAndProjectCatalog() async {
        let base = ScopedDiscoveryBase()
        let probe = ScopedOpenCodeProbeRecorder()
        let service = CachingAgentHarnessDiscoveryService(base: ProjectScopedOpenCodeDiscoveryService(
            base: base, projectTrustService: DefaultAgentProjectTrustService(), probe: { await probe.run($0) }
        ))
        let project = URL(fileURLWithPath: "/workspace/project")
        _ = await service.harnessStatuses(projectURL: project)
        await base.setVersion("refreshed")
        await service.refresh()
        let statuses = await service.harnessStatuses(projectURL: project)
        let calls = await base.projectURLs
        let paths = await probe.paths

        XCTAssertEqual(statuses[.opencode]?.availability?.versionDescription, "refreshed")
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(paths, [project.path, project.path])
    }

    func testProjectReadWaitsWhileExplicitRefreshClearsScopedCaches() async {
        let base = ScopedDiscoveryBase()
        let service = CachingAgentHarnessDiscoveryService(base: base)
        await service.warm()
        await base.setVersion("refreshed")
        let gate = MockShellRunnerGate()
        let invalidationStarted = expectation(description: "Scoped invalidation started")
        await base.holdInvalidation(gate: gate) { invalidationStarted.fulfill() }
        let refresh = Task { await service.refresh() }
        await fulfillment(of: [invalidationStarted], timeout: 2)

        let global = await service.harnessStatuses(projectURL: nil)
        let completed = expectation(description: "Project waits for the replacement metadata")
        let read = Task {
            let statuses = await service.harnessStatuses(projectURL: URL(fileURLWithPath: "/workspace/project"))
            completed.fulfill()
            return statuses
        }
        let earlyCompletion = await XCTWaiter.fulfillment(of: [completed], timeout: 0.1)
        gate.open()
        await refresh.value
        let statuses = await read.value
        let calls = await base.projectURLs

        XCTAssertEqual(earlyCompletion, .timedOut)
        XCTAssertEqual(global[.opencode]?.availability?.versionDescription, "original")
        XCTAssertEqual(statuses[.opencode]?.availability?.versionDescription, "refreshed")
        XCTAssertEqual(calls.count, 2)
    }

    func testProjectReadRetriesWhenRefreshSupersedesItsScopedProbe() async {
        let base = ScopedDiscoveryBase()
        let probe = ScopedOpenCodeProbeRecorder()
        await probe.hold()
        let started = expectation(description: "Scoped probe started")
        await probe.onNextStart { started.fulfill() }
        let service = CachingAgentHarnessDiscoveryService(base: ProjectScopedOpenCodeDiscoveryService(
            base: base, projectTrustService: DefaultAgentProjectTrustService(), probe: { await probe.run($0) }
        ))
        let read = Task { await service.harnessStatuses(projectURL: URL(fileURLWithPath: "/workspace/project")) }
        await fulfillment(of: [started], timeout: 2)
        await base.setVersion("refreshed")
        await service.refresh()
        await probe.release()
        let statuses = await read.value
        let paths = await probe.paths

        XCTAssertEqual(statuses[.opencode]?.availability?.versionDescription, "refreshed")
        XCTAssertEqual(paths, ["/workspace/project", "/workspace/project"])
    }

    func testDisabledOrMissingOpenCodeDoesNotStartAProjectProbe() async {
        for (enabled, installation) in [(false, AgentHarnessInstallationState.installed), (true, .missing)] {
            let base = ScopedDiscoveryBase()
            await base.configureOpenCode(enabled: enabled, installation: installation)
            let probe = ScopedOpenCodeProbeRecorder()
            let service = CachingAgentHarnessDiscoveryService(base: ProjectScopedOpenCodeDiscoveryService(
                base: base, projectTrustService: DefaultAgentProjectTrustService(), probe: { await probe.run($0) }
            ))
            let statuses = await service.harnessStatuses(projectURL: URL(fileURLWithPath: "/workspace/project"))
            let paths = await probe.paths

            XCTAssertTrue(paths.isEmpty)
            XCTAssertEqual(statuses[.opencode]?.installation, installation)
            XCTAssertEqual(statuses[.opencode]?.isEnabled, enabled)
            XCTAssertEqual(statuses[.claude]?.projectTrust, .notRequired)
        }
    }
}

private actor ScopedOpenCodeProbeRecorder {
    private(set) var paths: [String] = []
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var started: (@Sendable () -> Void)?

    func hold() { held = true }
    func onNextStart(_ callback: @escaping @Sendable () -> Void) { started = callback }

    func release() {
        held = false
        let pending = waiters
        waiters.removeAll()
        for continuation in pending { continuation.resume() }
    }

    func run(_ directory: URL) async -> OpenCodeDiscoverySnapshot {
        paths.append(directory.path)
        let callback = started
        started = nil
        callback?()
        if held { await withCheckedContinuation { waiters.append($0) } }
        if directory.lastPathComponent == "broken" {
            return OpenCodeDiscoverySnapshot(version: "1.18.31", models: [], readiness: .failed,
                                             diagnostics: ["Project configuration failed"])
        }
        let id = "local/\(directory.lastPathComponent)"
        let model = AgentModelOption(harnessId: .opencode, id: id, model: id, label: directory.lastPathComponent)
        return OpenCodeDiscoverySnapshot(version: "1.18.31", models: [model], readiness: .ready, diagnostics: [])
    }
}

private actor ScopedDiscoveryBase: AgentHarnessDiscoveryService {
    private(set) var projectURLs: [URL?] = []
    private var version = "original"
    private var enabled = true
    private var installation: AgentHarnessInstallationState = .installed
    private var held = false
    private var pending: [Int: CheckedContinuation<Void, Never>] = [:]
    private var callWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var invalidationGate: MockShellRunnerGate?
    private var invalidationStarted: (@Sendable () -> Void)?

    func hold() { held = true }
    func setVersion(_ value: String) { version = value }
    func configureOpenCode(enabled: Bool, installation: AgentHarnessInstallationState) {
        self.enabled = enabled
        self.installation = installation
    }
    func release(call: Int) { pending.removeValue(forKey: call)?.resume() }
    func release() {
        held = false
        let waiters = Array(pending.values)
        pending.removeAll()
        for waiter in waiters { waiter.resume() }
    }
    func waitForCalls(_ count: Int) async {
        if projectURLs.count < count { await withCheckedContinuation { callWaiters.append((count, $0)) } }
    }

    func holdInvalidation(gate: MockShellRunnerGate, onStart: @escaping @Sendable () -> Void) {
        invalidationGate = gate
        invalidationStarted = onStart
    }

    func invalidateDiscoveryCaches() async {
        invalidationStarted?()
        await invalidationGate?.wait()
    }

    func applyingProjectScope(
        to statuses: [AgentHarnessID: AgentHarnessStatus], projectURL: URL
    ) async -> [AgentHarnessID: AgentHarnessStatus] { statuses }

    func harnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] {
        projectURLs.append(projectURL)
        let call = projectURLs.count
        let ready = callWaiters.filter { $0.0 <= call }
        callWaiters.removeAll { $0.0 <= call }
        for waiter in ready { waiter.1.resume() }
        let statuses: [AgentHarnessID: AgentHarnessStatus] = [
            .opencode: AgentHarnessStatus(harnessId: .opencode, installation: installation,
                                          availability: AgentHarnessAvailability(harnessId: .opencode,
                                                                               executablePath: "/bin/opencode", versionDescription: version),
                                          isEnabled: enabled, setup: .needsSetup,
                                          projectTrust: projectURL == nil ? nil : .notRequired,
                                          diagnostics: ["Global credentials missing"]),
            .claude: AgentHarnessStatus(harnessId: .claude, installation: .installed, setup: .ready)
        ]
        if held { await withCheckedContinuation { pending[call] = $0 } }
        return statuses
    }

    func installedHarnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] {
        await harnessStatuses(projectURL: projectURL)
    }

    func availableHarnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] {
        await harnessStatuses(projectURL: projectURL)
    }

    func modelOptions(for harnessId: AgentHarnessID) async -> [AgentModelOption] {
        [AgentModelOption(harnessId: harnessId, id: "global/model", model: "global/model", label: "Global model")]
    }

    func stableHarnessOrdering() async -> [AgentHarnessID] { [.claude, .opencode] }
}

extension ScopedDiscoveryBase: AgentHarnessDiscoveryCacheInvalidating, AgentHarnessProjectScopeApplying {}

private actor ScopedTrustRecorder: AgentProjectTrustService {
    private var trust: AgentProjectTrustStatus = .notTrusted
    func setTrust(_ trust: AgentProjectTrustStatus) { self.trust = trust }
    nonisolated func cachedStatus(harnessId: AgentHarnessID, projectURL: URL) -> AgentProjectTrustStatus { .unknown }
    func status(harnessId: AgentHarnessID, projectURL: URL) async -> AgentProjectTrustStatus {
        harnessId == .opencode ? .notRequired : trust
    }
    func trustProject(harnessId: AgentHarnessID, projectURL: URL) async throws { trust = .trusted }
}

private final class ScopedDiscoveryClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_000)
    var now: Date { lock.withLock { value } }
    func advance(_ interval: TimeInterval) { lock.withLock { value += interval } }
}

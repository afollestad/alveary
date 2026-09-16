import AgentCLIKit
import XCTest

@testable import Alveary

/// How `refreshHarnessStatuses` treats the shared discovery cache. The screen's plain
/// load-and-render behavior stays in the base file; this covers the invalidation contract.
@MainActor
extension SettingsViewModelTests {
    func testRefreshHarnessStatusesInvalidatesTheSharedCacheBeforeItProbes() async {
        let discovery = RecordingHarnessDiscoveryService(statuses: [:])
        let box = InvalidationProbeBox()
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(),
            harnessDiscovery: discovery,
            invalidateHarnessDiscoveryCache: {
                box.probesSeenAtInvalidation = await discovery.harnessStatusesInvocations()
            }
        )

        await viewModel.refreshHarnessStatuses()

        // Zero, not nil: the invalidation ran, and ran first. The ordering is the invariant —
        // invalidating after the read would leave the probe answered from the still-valid
        // shared cache, exactly the staleness this screen must never show.
        XCTAssertEqual(box.probesSeenAtInvalidation, 0)
        let probes = await discovery.harnessStatusesInvocations()
        XCTAssertEqual(probes, 1)
    }

    func testActivationRecoversUpdatedOpenCodeAndStopsRecheckingOnceReady() async {
        let ready = openCodeRefreshStatus(version: "1.18.31", setup: .ready)
        let discovery = RecordingHarnessDiscoveryService(statuses: [.opencode: ready])
        var settings = AppSettings()
        settings.defaultHarness = "opencode"
        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService(current: settings), harnessDiscovery: discovery)
        viewModel.harnessStatuses = ["opencode": openCodeRefreshStatus(version: "1.18.21", setup: .failed)]
        viewModel.hasLoadedHarnessStatuses = true

        await viewModel.refreshHarnessStatusesAfterActivation()

        XCTAssertEqual(viewModel.harnessStatuses["opencode"], ready)
        XCTAssertEqual(viewModel.shortStatusLabel(for: ready), "Ready")
        XCTAssertEqual(viewModel.harnessVersion(for: ready), "1.18.31")
        XCTAssertTrue(viewModel.hasLoadedHarnessStatuses)
        await viewModel.refreshHarnessStatusesAfterActivation()
        let probes = await discovery.harnessStatusesInvocations()
        XCTAssertEqual(probes, 1)
    }

    func testActivationDoesNotDuplicatePendingChecksOrProbeDisabledHarnesses() async {
        let discovery = RecordingHarnessDiscoveryService(statuses: [:])
        let settings = InMemorySettingsService()
        let viewModel = SettingsViewModel(settingsService: settings, harnessDiscovery: discovery)
        viewModel.harnessStatuses = ["opencode": openCodeRefreshStatus(version: "1.18.21", setup: .failed)]

        await viewModel.refreshHarnessStatusesAfterActivation()
        viewModel.hasLoadedHarnessStatuses = true
        settings.update { $0.setHarness("opencode", enabled: false) }
        await viewModel.refreshHarnessStatusesAfterActivation()

        let probes = await discovery.harnessStatusesInvocations()
        XCTAssertEqual(probes, 0)
    }

    func testOlderHarnessRefreshCannotRestoreErrorAfterNewerCheckRecovers() async {
        let started = expectation(description: "First discovery is suspended")
        let ready = openCodeRefreshStatus(version: "1.18.31", setup: .ready)
        let discovery = SuspendedSettingsHarnessDiscovery(
            old: openCodeRefreshStatus(version: "1.18.21", setup: .failed), new: ready,
            didStart: { started.fulfill() }
        )
        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService(), harnessDiscovery: discovery)
        let first = Task { await viewModel.refreshHarnessStatuses() }
        await fulfillment(of: [started], timeout: 2)

        await viewModel.refreshHarnessStatuses()
        XCTAssertEqual(viewModel.harnessStatuses["opencode"], ready)
        XCTAssertTrue(viewModel.hasLoadedHarnessStatuses)
        await discovery.releaseFirstRead()
        await first.value

        XCTAssertEqual(viewModel.harnessStatuses["opencode"], ready)
        XCTAssertTrue(viewModel.hasLoadedHarnessStatuses)
    }

    private func openCodeRefreshStatus(version: String, setup: AgentHarnessReadinessState) -> AgentHarnessStatus {
        AgentHarnessStatus(
            harnessId: .opencode, definition: OpenCodeHarnessDefinition.definition, installation: .installed,
            availability: AgentHarnessAvailability(
                harnessId: .opencode, executablePath: "/test/opencode", versionDescription: version
            ),
            setup: setup,
            diagnostics: setup == .failed ? ["Unsupported OpenCode version \(version)"] : []
        )
    }
}

/// Captures what the injected invalidation closure observed; a `@Sendable` closure cannot write
/// a captured local.
private final class InvalidationProbeBox: @unchecked Sendable {
    var probesSeenAtInvalidation: Int?
}

/// Allows the previous failure to arrive after a successful retry, independently of discovery's own cache.
private actor SuspendedSettingsHarnessDiscovery: AgentHarnessDiscoveryService {
    private let old: AgentHarnessStatus
    private let new: AgentHarnessStatus
    private let didStart: @Sendable () -> Void
    private var firstRead: CheckedContinuation<[AgentHarnessID: AgentHarnessStatus], Never>?
    private var hasStarted = false

    init(old: AgentHarnessStatus, new: AgentHarnessStatus, didStart: @escaping @Sendable () -> Void) {
        self.old = old
        self.new = new
        self.didStart = didStart
    }

    func harnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] {
        guard !hasStarted else { return [.opencode: new] }
        hasStarted = true
        return await withCheckedContinuation {
            firstRead = $0
            didStart()
        }
    }

    func releaseFirstRead() {
        firstRead?.resume(returning: [.opencode: old])
        firstRead = nil
    }

    func installedHarnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] { [.opencode: new] }
    func availableHarnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] { [.opencode: new] }
    func modelOptions(for harnessId: AgentHarnessID) async -> [AgentModelOption] { [] }
    func stableHarnessOrdering() async -> [AgentHarnessID] { [.opencode] }
}

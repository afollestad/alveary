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
}

/// Captures what the injected invalidation closure observed; a `@Sendable` closure cannot write
/// a captured local.
private final class InvalidationProbeBox: @unchecked Sendable {
    var probesSeenAtInvalidation: Int?
}

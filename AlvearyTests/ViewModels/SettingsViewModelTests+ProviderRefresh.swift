import AgentCLIKit
import XCTest

@testable import Alveary

/// How `refreshProviderStatuses` treats the shared discovery cache. The screen's plain
/// load-and-render behavior stays in the base file; this covers the invalidation contract.
@MainActor
extension SettingsViewModelTests {
    func testRefreshProviderStatusesInvalidatesTheSharedCacheBeforeItProbes() async {
        let discovery = RecordingProviderDiscoveryService(statuses: [:])
        let box = InvalidationProbeBox()
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(),
            providerDiscovery: discovery,
            invalidateProviderDiscoveryCache: {
                box.probesSeenAtInvalidation = await discovery.providerStatusesInvocations()
            }
        )

        await viewModel.refreshProviderStatuses()

        // Zero, not nil: the invalidation ran, and ran first. The ordering is the invariant —
        // invalidating after the read would leave the probe answered from the still-valid
        // shared cache, exactly the staleness this screen must never show.
        XCTAssertEqual(box.probesSeenAtInvalidation, 0)
        let probes = await discovery.providerStatusesInvocations()
        XCTAssertEqual(probes, 1)
    }
}

/// Captures what the injected invalidation closure observed; a `@Sendable` closure cannot write
/// a captured local.
private final class InvalidationProbeBox: @unchecked Sendable {
    var probesSeenAtInvalidation: Int?
}

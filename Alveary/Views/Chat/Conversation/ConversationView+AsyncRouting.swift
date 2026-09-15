import AgentCLIKit
import Foundation
import SwiftData

extension ConversationView {
    var composerHarnessStatusTaskID: String {
        Self.composerHarnessStatusCacheKey(
            projectURL: harnessDiscoveryProjectURL,
            activeHarnessID: activeHarnessID,
            settings: settingsService.current
        )
    }

    func refreshComposerHarnessStatuses() async {
        let projectURL = harnessDiscoveryProjectURL
        let request = ConversationAsyncRouting.HarnessStatusRequest(
            key: Self.composerHarnessStatusCacheKey(
                projectURL: projectURL,
                activeHarnessID: activeHarnessID,
                settings: settingsService.current
            ),
            projectURL: projectURL
        )
        // Thread switches create a fresh `ConversationView`; seed it from the
        // last successful discovery result so model-scoped effort labels do not
        // temporarily disappear while async harness discovery warms back up.
        //
        // Keyed on the *new* request key, not the mount: `init`'s seed belongs to the key this
        // view was built with, so a draft project reassignment must re-seed here or honestly
        // report not-loaded. Clearing the flag unconditionally emptied the model list and put
        // Goal mode back to "Checking..." on every mount, defeating that seeding.
        if let seeded = ConversationAsyncRouting.seededHarnessStatusSnapshot(for: request) {
            composerHarnessOrdering = seeded.ordering
            composerHarnessStatuses = seeded.statuses
            hasLoadedComposerHarnessStatuses = true
        } else {
            hasLoadedComposerHarnessStatuses = false
        }

        guard let result = await ConversationAsyncRouting.loadHarnessStatuses(
            request: request,
            harnessDiscovery: harnessDiscovery,
            currentRequestKey: { composerHarnessStatusTaskID }
        ) else {
            return
        }

        ConversationAsyncRouting.applyHarnessStatusResult(result) { snapshot in
            composerHarnessOrdering = snapshot.ordering
            composerHarnessStatuses = snapshot.statuses
            hasLoadedComposerHarnessStatuses = true
        }
    }
}

enum ConversationAsyncRouting {
    struct HarnessStatusRequest {
        let key: String
        let projectURL: URL?
    }

    struct HarnessStatusResult {
        let requestKey: String
        let snapshot: ComposerHarnessStatusSnapshot
    }

    @MainActor
    static func loadHarnessStatuses(
        request: HarnessStatusRequest,
        harnessDiscovery: any AgentCLIKit.AgentHarnessDiscoveryService,
        currentRequestKey: @escaping @MainActor () -> String
    ) async -> HarnessStatusResult? {
        async let ordering = harnessDiscovery.stableHarnessOrdering()
        async let statuses = harnessDiscovery.harnessStatuses(projectURL: request.projectURL)
        let (resolvedOrdering, resolvedStatuses) = await (ordering, statuses)
        let snapshot = ComposerHarnessStatusSnapshot(ordering: resolvedOrdering, statuses: resolvedStatuses)

        // Draft project reassignment preserves this view's identity. A discovery
        // started for the previous project must not update state or seed its cache.
        guard !Task.isCancelled, currentRequestKey() == request.key else {
            return nil
        }
        return HarnessStatusResult(requestKey: request.key, snapshot: snapshot)
    }

    /// The snapshot a refresh may keep showing while its own probe runs, or `nil` when this key
    /// has never resolved. Exists as a static so `ConversationViewAsyncRoutingTests` can reach the
    /// lookup without hosting the view.
    @MainActor
    static func seededHarnessStatusSnapshot(for request: HarnessStatusRequest) -> ComposerHarnessStatusSnapshot? {
        ComposerHarnessStatusCache.snapshot(for: request.key)
    }

    @MainActor
    static func applyHarnessStatusResult(
        _ result: HarnessStatusResult,
        updateState: (ComposerHarnessStatusSnapshot) -> Void
    ) {
        updateState(result.snapshot)
        ComposerHarnessStatusCache.store(result.snapshot, for: result.requestKey)
    }

}

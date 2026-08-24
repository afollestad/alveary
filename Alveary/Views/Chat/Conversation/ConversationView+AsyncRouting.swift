import AgentCLIKit
import Foundation
import SwiftData

extension ConversationView {
    var composerProviderStatusTaskID: String {
        Self.composerProviderStatusCacheKey(
            projectURL: providerDiscoveryProjectURL,
            activeProviderID: activeProviderID,
            settings: settingsService.current
        )
    }

    func refreshComposerProviderStatuses() async {
        let projectURL = providerDiscoveryProjectURL
        let request = ConversationAsyncRouting.ProviderStatusRequest(
            key: Self.composerProviderStatusCacheKey(
                projectURL: projectURL,
                activeProviderID: activeProviderID,
                settings: settingsService.current
            ),
            projectURL: projectURL
        )
        // Thread switches create a fresh `ConversationView`; seed it from the
        // last successful discovery result so model-scoped effort labels do not
        // temporarily disappear while async provider discovery warms back up.
        //
        // Keyed on the *new* request key, not the mount: `init`'s seed belongs to the key this
        // view was built with, so a draft project reassignment must re-seed here or honestly
        // report not-loaded. Clearing the flag unconditionally emptied the model list and put
        // Goal mode back to "Checking..." on every mount, defeating that seeding.
        if let seeded = ConversationAsyncRouting.seededProviderStatusSnapshot(for: request) {
            composerProviderOrdering = seeded.ordering
            composerProviderStatuses = seeded.statuses
            hasLoadedComposerProviderStatuses = true
        } else {
            hasLoadedComposerProviderStatuses = false
        }

        guard let result = await ConversationAsyncRouting.loadProviderStatuses(
            request: request,
            providerDiscovery: providerDiscovery,
            currentRequestKey: { composerProviderStatusTaskID }
        ) else {
            return
        }

        ConversationAsyncRouting.applyProviderStatusResult(result) { snapshot in
            composerProviderOrdering = snapshot.ordering
            composerProviderStatuses = snapshot.statuses
            hasLoadedComposerProviderStatuses = true
        }
    }
}

enum ConversationAsyncRouting {
    struct ProviderStatusRequest {
        let key: String
        let projectURL: URL?
    }

    struct ProviderStatusResult {
        let requestKey: String
        let snapshot: ComposerProviderStatusSnapshot
    }

    struct DiffSwitchRequest {
        let threadID: PersistentIdentifier
        let workingDirectory: String
        let allowsThreadScopedSwitch: Bool

        init(
            threadID: PersistentIdentifier,
            workingDirectory: String,
            allowsThreadScopedSwitch: Bool = true
        ) {
            self.threadID = threadID
            self.workingDirectory = workingDirectory
            self.allowsThreadScopedSwitch = allowsThreadScopedSwitch
        }
    }

    struct DiffSwitchLiveState {
        let selectedSidebarItem: @MainActor () -> SidebarItem?
        let currentWorkingDirectory: @MainActor () -> String?
        let resolveScope: @MainActor () -> DiffViewerSwitchScope
    }

    @MainActor
    static func loadProviderStatuses(
        request: ProviderStatusRequest,
        providerDiscovery: any AgentCLIKit.AgentProviderDiscoveryService,
        currentRequestKey: @escaping @MainActor () -> String
    ) async -> ProviderStatusResult? {
        async let ordering = providerDiscovery.stableProviderOrdering()
        async let statuses = providerDiscovery.providerStatuses(projectURL: request.projectURL)
        let (resolvedOrdering, resolvedStatuses) = await (ordering, statuses)
        let snapshot = ComposerProviderStatusSnapshot(ordering: resolvedOrdering, statuses: resolvedStatuses)

        // Draft project reassignment preserves this view's identity. A discovery
        // started for the previous project must not update state or seed its cache.
        guard !Task.isCancelled, currentRequestKey() == request.key else {
            return nil
        }
        return ProviderStatusResult(requestKey: request.key, snapshot: snapshot)
    }

    /// The snapshot a refresh may keep showing while its own probe runs, or `nil` when this key
    /// has never resolved. Exists as a static so `ConversationViewAsyncRoutingTests` can reach the
    /// lookup without hosting the view.
    @MainActor
    static func seededProviderStatusSnapshot(for request: ProviderStatusRequest) -> ComposerProviderStatusSnapshot? {
        ComposerProviderStatusCache.snapshot(for: request.key)
    }

    @MainActor
    static func applyProviderStatusResult(
        _ result: ProviderStatusResult,
        updateState: (ComposerProviderStatusSnapshot) -> Void
    ) {
        updateState(result.snapshot)
        ComposerProviderStatusCache.store(result.snapshot, for: result.requestKey)
    }

    @MainActor
    static func warmFileCacheForDiffSwitch(
        request: DiffSwitchRequest,
        fileListManager: FileListManager,
        liveState: DiffSwitchLiveState,
        performSwitch: @escaping @MainActor (DiffViewerSwitchScope) async -> Void
    ) async {
        await fileListManager.warmCache(for: request.workingDirectory)

        // Cache warming can finish after navigation or an in-place draft project
        // reassignment, so claim the diff target only while both inputs still match.
        guard request.allowsThreadScopedSwitch,
              !Task.isCancelled,
              case .thread(let selectedThread) = liveState.selectedSidebarItem(),
              selectedThread.persistentModelID == request.threadID,
              liveState.currentWorkingDirectory() == request.workingDirectory else {
            return
        }
        await performSwitch(liveState.resolveScope())
    }
}

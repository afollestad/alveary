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
        hasLoadedComposerProviderStatuses = false
        guard let result = await ConversationAsyncRouting.loadProviderStatuses(
            request: request,
            providerDiscovery: providerDiscovery,
            currentRequestKey: { composerProviderStatusTaskID }
        ) else {
            return
        }

        // Thread switches create a fresh `ConversationView`; seed it from the
        // last successful discovery result so model-scoped effort labels do not
        // temporarily disappear while async provider discovery warms back up.
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
        selectedSidebarItem: @escaping @MainActor () -> SidebarItem?,
        currentWorkingDirectory: @escaping @MainActor () -> String?,
        performSwitch: @escaping @MainActor () async -> Void
    ) async {
        await fileListManager.warmCache(for: request.workingDirectory)

        // Cache warming can finish after navigation or an in-place draft project
        // reassignment, so claim the diff target only while both inputs still match.
        guard request.allowsThreadScopedSwitch,
              !Task.isCancelled,
              case .thread(let selectedThread) = selectedSidebarItem(),
              selectedThread.persistentModelID == request.threadID,
              currentWorkingDirectory() == request.workingDirectory else {
            return
        }
        await performSwitch()
    }
}

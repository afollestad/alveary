import AgentCLIKit
import Foundation
import SwiftData

/// What `start` hands back. The conversation is answered as soon as the thread exists so the
/// caller can navigate immediately; everything that still has to happen rides `dispatch`.
///
/// Deliberately a plain value rather than a nested type, so the pane's view model can name it
/// without reaching for the service.
struct PullRequestAgenticThreadStart {
    /// The new thread's sole-main-conversation id, which is what the caller navigates to.
    let conversationID: String
    /// Links the pull request, resolves the workspace when one is still owed, then dispatches the
    /// first prompt — in that order, behind the navigation. Await it only to surface a failure;
    /// nothing else may depend on it.
    let dispatch: Task<Void, Error>
}

/// Starts the agentic threads the pull request pane's footer offers: a Task thread whose first
/// prompt asks for the work the way the user would. The agent picks the workflow up from the
/// `alveary_host` tools — an instructions tool first, and the matching writer last.
///
/// The two kinds differ in three places and nowhere else: the thread's name, its first prompt,
/// and whether it gets a checkout. Everything below — seed resolution, the degrade-never-refuse
/// rules, answering as soon as the thread exists, link-then-dispatch ordering — is shared, which
/// is why a second caller uses this service rather than copying it.
@MainActor
final class PullRequestAgenticThreadService {
    /// Which half of a pull request's life the thread is for.
    enum Kind: Equatable, CaseIterable {
        /// Read the pull request and propose a review. Project-less on purpose: every step runs
        /// through host tools against GitHub, and a project worktree would have the agent
        /// reviewing whatever is checked out there rather than the pull request.
        case review
        /// Answer the feedback the pull request already received, which means editing files,
        /// running checks, and pushing — so this one wants the head branch checked out.
        case addressFeedback

        var needsCheckout: Bool {
            self == .addressFeedback
        }

        /// Named up front rather than left to provider auto-naming: the sidebar row is meaningful
        /// the moment the user lands on it.
        func threadName(for identifier: PullRequestIdentifier) -> String {
            switch self {
            case .review:
                "Review \(identifier.displayKey)"
            case .addressFeedback:
                "Address feedback \(identifier.displayKey)"
            }
        }

        /// Reads like something the user would type, because that is what it stands in for. The
        /// URL alone names the pull request — the instructions tool fetches the title itself, so
        /// repeating the shorthand or title here would only pad the bubble.
        func requestPrompt(url: URL) -> String {
            switch self {
            case .review:
                "Review pull request: \(url.absoluteString)"
            case .addressFeedback:
                "Address feedback on pull request: \(url.absoluteString)"
            }
        }
    }

    enum StartError: LocalizedError, Equatable {
        case noReadyProvider
        case conversationMissing

        var errorDescription: String? {
            switch self {
            case .noReadyProvider:
                return "No agent is ready to start this thread. Check the Agents settings."
            case .conversationMissing:
                return "The thread could not be started."
            }
        }
    }

    /// The validated settings a spawned thread is seeded with.
    struct SeedSettings: Equatable {
        let provider: String
        let model: String?
        let effort: String
        let permissionMode: String
    }

    let lifecycleService: ThreadLifecycleService
    let worktreeManager: any WorktreeManager
    let taskWorkspaceOwnershipService: any TaskWorkspaceOwnershipService
    let directoryExists: @Sendable (String) -> Bool
    private let linkService: PullRequestLinkService
    private let pullRequestsService: any PullRequestsService
    private let settingsService: any SettingsService
    private let providerDiscovery: (any AgentProviderDiscoveryService)?
    private let startInitialPrompt: @MainActor (Conversation, String) -> Void

    init(
        lifecycleService: ThreadLifecycleService,
        linkService: PullRequestLinkService,
        pullRequestsService: any PullRequestsService,
        settingsService: any SettingsService,
        worktreeManager: any WorktreeManager,
        taskWorkspaceOwnershipService: any TaskWorkspaceOwnershipService,
        providerDiscovery: (any AgentProviderDiscoveryService)? = nil,
        directoryExists: @escaping @Sendable (String) -> Bool = { path in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            return exists && isDirectory.boolValue
        },
        startInitialPrompt: @escaping @MainActor (Conversation, String) -> Void
    ) {
        self.lifecycleService = lifecycleService
        self.linkService = linkService
        self.pullRequestsService = pullRequestsService
        self.settingsService = settingsService
        self.worktreeManager = worktreeManager
        self.taskWorkspaceOwnershipService = taskWorkspaceOwnershipService
        self.providerDiscovery = providerDiscovery
        self.directoryExists = directoryExists
        self.startInitialPrompt = startInitialPrompt
    }

    /// Creates the thread and answers the moment it exists, so the caller can navigate without
    /// waiting on GitHub. Linking, any deferred checkout, and the first prompt run behind that
    /// navigation on the returned `dispatch` — linking used to sit in front of the return, which
    /// put a `gh` round trip between the footer click and the sidebar selection.
    ///
    /// `knownDetail` lets a caller that already fetched this pull request — the pane always has —
    /// spare the link its own round trip, and hands the checkout ladder the head branch without
    /// one either.
    func start(
        kind: Kind,
        identifier: PullRequestIdentifier,
        url: URL,
        knownDetail: PullRequestDetail? = nil,
        preferredProjectID: PersistentIdentifier? = nil
    ) async throws -> PullRequestAgenticThreadStart {
        let settings = settingsService.current
        let seed = try await resolvedSeedSettings(settings: settings)
        let threadName = kind.threadName(for: identifier)
        // The link ignores a detail naming a different pull request and fetches its own; the
        // ladder must not trust one either, or the checkout lands on that other pull request's
        // head branch.
        let trustedDetail = knownDetail?.id == identifier ? knownDetail : nil
        // Only the rungs that are pure local reads run here; a worktree checkout is a fetch plus a
        // git command, far too slow to sit in front of the navigation, so it rides `dispatch`.
        let borrowed = kind.needsCheckout
            ? borrowedWorkspace(identifier: identifier, headRefName: trustedDetail?.headRefName)
            : nil

        let thread = try lifecycleService.insertTaskThread(
            seed: Self.threadSeed(seed, name: threadName, workspace: borrowed)
        )
        guard let conversation = thread.soleMainConversation else {
            throw StartError.conversationMissing
        }
        // Snapshotted before the dispatch task, which suspends and can invalidate the models.
        let threadID = thread.persistentModelID
        let conversationID = conversation.id
        let needsWorkspace = kind.needsCheckout && borrowed == nil

        return PullRequestAgenticThreadStart(
            conversationID: conversationID,
            // `self` is captured on purpose: the deferred workspace upgrade needs the service's
            // own collaborators, and this service is app-scoped, so the task cannot outlive it.
            dispatch: Task { @MainActor [self] in
                let detail = await resolvedDetail(
                    knownDetail: trustedDetail,
                    identifier: identifier,
                    fetchWhenMissing: needsWorkspace
                )
                // Linked before the prompt is dispatched, not after: this route links regardless
                // of `automaticallyLinkPullRequests`, and doing it first means transcript
                // detection finds the pull request already linked and asks no redundant
                // "link this?" question under the prompt. Best-effort — a GitHub hiccup must not
                // stop a thread from starting.
                _ = try? await linkService.link(
                    identifier,
                    owner: .thread(threadID),
                    detail: detail
                )
                if needsWorkspace {
                    await upgradeWorkspace(
                        threadID: threadID,
                        identifier: identifier,
                        headRefName: detail?.headRefName,
                        threadName: threadName,
                        preferredProjectID: preferredProjectID
                    )
                }

                // Re-resolved after the await rather than carried across it.
                guard let liveThread = lifecycleService.modelContext.resolveThread(id: threadID),
                      let conversation = liveThread.soleMainConversation else {
                    throw StartError.conversationMissing
                }
                // Deliberately short. The instructions are not inlined here — the agent fetches
                // them with the matching instructions tool, exactly as it does when the user asks
                // for the same work in a thread that already exists, so both routes run one shared
                // path and show the same card.
                startInitialPrompt(conversation, kind.requestPrompt(url: url))
            }
        )
    }

    /// The workspace's own root is the only grant either kind needs: a review reaches GitHub
    /// through host tools, and addressing feedback works inside its checkout.
    private static func threadSeed(
        _ seed: SeedSettings,
        name: String,
        workspace: TaskWorkspaceDescriptor?
    ) -> TaskThreadSeed {
        TaskThreadSeed(
            provider: seed.provider,
            permissionMode: seed.permissionMode,
            model: seed.model,
            effort: seed.effort,
            isDraft: false,
            name: name,
            grantedRoots: [],
            workspace: workspace
        )
    }

    /// One fetch serving two readers: the link stores the detail's summary, and the checkout
    /// ladder reads its head branch. Only the ladder is worth a round trip of its own — without it
    /// the link fetches lazily, as it always has. Best-effort either way; a nil here costs the
    /// thread its checkout, not its start.
    private func resolvedDetail(
        knownDetail: PullRequestDetail?,
        identifier: PullRequestIdentifier,
        fetchWhenMissing: Bool
    ) async -> PullRequestDetail? {
        if let knownDetail {
            return knownDetail
        }
        guard fetchWhenMissing else {
            return nil
        }
        return try? await pullRequestsService.fetchDetail(identifier)
    }

    private func resolvedSeedSettings(settings: AppSettings) async throws -> SeedSettings {
        let resolution = await resolvedThreadDefaults(settings: settings)
        let provider = try resolvedProvider(settings: settings, resolution: resolution)
        let options = await modelOptions(for: provider, resolution: resolution)
        return Self.resolveSeedSettings(
            settings: settings,
            resolution: resolution,
            provider: provider,
            modelOptions: options
        )
    }

    /// Degrade, never fail. A model or effort the provider stopped offering falls back to what a
    /// typed thread would get, because refusing to start would leave the user with an error and no
    /// way to see why from the footer. Only "nothing can run at all" is an error, and that is
    /// caught before this runs.
    static func resolveSeedSettings(
        settings: AppSettings,
        resolution: ThreadDefaultResolution,
        provider: String,
        modelOptions: [AgentModelOption]
    ) -> SeedSettings {
        let inheritsResolution = provider == resolution.providerID
        let model = resolvedModel(
            settings: settings,
            resolution: resolution,
            options: modelOptions,
            inheritsResolution: inheritsResolution
        )
        let effort = resolvedEffort(
            settings: settings,
            resolution: resolution,
            options: modelOptions,
            model: model,
            inheritsResolution: inheritsResolution
        )
        let permissionMode = inheritsResolution
            ? resolution.permissionMode
            : AppSettings.defaultPermissionMode(forProvider: provider)
        return SeedSettings(provider: provider, model: model, effort: effort, permissionMode: permissionMode)
    }

    private static func resolvedModel(
        settings: AppSettings,
        resolution: ThreadDefaultResolution,
        options: [AgentModelOption],
        inheritsResolution: Bool
    ) -> String? {
        let inherited = inheritsResolution ? resolution.storedThreadModel : nil
        guard let requested = settings.pullRequestReviewModel,
              let option = AgentModelOptionSelection.option(in: options, matching: requested) else {
            return inherited
        }
        let stored = AgentModelOptionSelection.storedModelValue(for: option)
        return stored == AppSettings.defaultModelValue ? nil : stored
    }

    private static func resolvedEffort(
        settings: AppSettings,
        resolution: ThreadDefaultResolution,
        options: [AgentModelOption],
        model: String?,
        inheritsResolution: Bool
    ) -> String {
        let inherited = inheritsResolution ? resolution.effort : AppSettings.defaultEffortLevel
        guard let requested = settings.pullRequestReviewEffort else {
            return AgentModelOptionSelection.normalizedEffort(inherited, options: options, selectedModel: model)
        }
        // An empty supported list means the provider reports no effort catalog, which is not the
        // same as rejecting the value.
        let supported = AgentModelOptionSelection.effortOptions(in: options, selectedModel: model)
        guard supported.isEmpty || supported.contains(where: { $0.value == requested }) else {
            return AgentModelOptionSelection.normalizedEffort(inherited, options: options, selectedModel: model)
        }
        return requested
    }

    /// The pinned provider only applies while it is actually ready; otherwise the thread follows
    /// the Threads defaults, like every other setting here.
    private func resolvedProvider(settings: AppSettings, resolution: ThreadDefaultResolution) throws -> String {
        if let requested = settings.pullRequestReviewProvider,
           resolution.readyProviderIDs.contains(requested) {
            return requested
        }
        guard let providerID = resolution.providerID else {
            throw StartError.noReadyProvider
        }
        return providerID
    }

    private func resolvedThreadDefaults(settings: AppSettings) async -> ThreadDefaultResolution {
        if let providerDiscovery {
            return await ThreadDefaultResolver.resolve(settings: settings, providerDiscovery: providerDiscovery)
        }
        return ThreadDefaultResolver.resolve(
            settings: settings,
            providerOrdering: AppSettings.supportedProviderIDs,
            providerStatuses: [:],
            allowStaticFallback: true
        )
    }

    /// Mirrors `ThreadHostToolService.modelOptions(for:resolution:)`: the resolution only carries
    /// the default provider's catalog, so a pinned non-default provider asks discovery for its own.
    private func modelOptions(
        for provider: String,
        resolution: ThreadDefaultResolution
    ) async -> [AgentModelOption] {
        if provider == resolution.providerID, !resolution.modelOptions.isEmpty {
            return resolution.modelOptions
        }
        if let providerDiscovery, let providerID = AgentProviderID(rawValue: provider) {
            let discovered = await providerDiscovery.modelOptions(for: providerID)
            if !discovered.isEmpty {
                return discovered
            }
        }
        return ThreadDefaultResolver.modelOptions(for: provider, providerStatuses: [:])
    }
}

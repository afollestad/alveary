import AgentCLIKit
import Foundation
import SwiftData

/// What `startReview` hands back. The conversation is answered as soon as the thread exists so
/// the caller can navigate immediately; everything that still has to happen rides `dispatch`.
///
/// Deliberately a plain value rather than a nested type, so the pane's view model can name it
/// without reaching for the service.
struct PullRequestAgenticReviewStart {
    /// The new thread's sole-main-conversation id, which is what the caller navigates to.
    let conversationID: String
    /// Links the pull request, then dispatches the first prompt — in that order, behind the
    /// navigation. Await it only to surface a failure; nothing else may depend on it.
    let dispatch: Task<Void, Error>
}

/// Starts the agentic review the pull request pane's footer offers: a Task thread whose first
/// prompt asks for the review the way the user would. The agent picks the workflow up from the
/// `alveary_host` tools — `get_pr_review_instructions` first, `propose_pr_review` last, which
/// lands the ordinary confirmation card.
///
/// The thread is project-less on purpose. Every step runs through host tools against GitHub, so
/// it needs no checkout — and a review that borrowed a project's worktree would be reviewing
/// whatever happened to be checked out there rather than the pull request.
@MainActor
final class PullRequestAgenticReviewService {
    enum StartError: LocalizedError, Equatable {
        case noReadyProvider
        case conversationMissing

        var errorDescription: String? {
            switch self {
            case .noReadyProvider:
                return "No agent is ready to run a review. Check the Agents settings."
            case .conversationMissing:
                return "The review thread could not be started."
            }
        }
    }

    /// The validated settings a review thread is seeded with.
    struct SeedSettings: Equatable {
        let provider: String
        let model: String?
        let effort: String
        let permissionMode: String
    }

    private let lifecycleService: ThreadLifecycleService
    private let linkService: PullRequestLinkService
    private let settingsService: any SettingsService
    private let providerDiscovery: (any AgentProviderDiscoveryService)?
    private let startInitialPrompt: @MainActor (Conversation, String) -> Void

    init(
        lifecycleService: ThreadLifecycleService,
        linkService: PullRequestLinkService,
        settingsService: any SettingsService,
        providerDiscovery: (any AgentProviderDiscoveryService)? = nil,
        startInitialPrompt: @escaping @MainActor (Conversation, String) -> Void
    ) {
        self.lifecycleService = lifecycleService
        self.linkService = linkService
        self.settingsService = settingsService
        self.providerDiscovery = providerDiscovery
        self.startInitialPrompt = startInitialPrompt
    }

    /// Creates the review thread and answers the moment it exists, so the caller can navigate
    /// without waiting on GitHub. Linking and the first prompt run behind that navigation on the
    /// returned `dispatch` — they used to sit in front of the return, which put a `gh` round trip
    /// between the footer click and the sidebar selection.
    ///
    /// `knownDetail` lets a caller that already fetched this pull request — the pane always has —
    /// spare the link its own round trip.
    func startReview(
        identifier: PullRequestIdentifier,
        url: URL,
        knownDetail: PullRequestDetail? = nil
    ) async throws -> PullRequestAgenticReviewStart {
        let settings = settingsService.current
        let seed = try await resolvedSeedSettings(settings: settings)

        let thread = try lifecycleService.insertTaskThread(
            seed: TaskThreadSeed(
                provider: seed.provider,
                permissionMode: seed.permissionMode,
                model: seed.model,
                effort: seed.effort,
                isDraft: false,
                // Named up front rather than left to provider auto-naming: the sidebar row is
                // meaningful the moment the user lands on it.
                name: "Review \(identifier.displayKey)",
                // The review reaches GitHub through host tools; it needs no filesystem access.
                grantedRoots: []
            )
        )
        guard let conversation = thread.soleMainConversation else {
            throw StartError.conversationMissing
        }
        // Snapshotted before the dispatch task, which suspends and can invalidate the models.
        let threadID = thread.persistentModelID
        let conversationID = conversation.id

        return PullRequestAgenticReviewStart(
            conversationID: conversationID,
            dispatch: Task { @MainActor [linkService, lifecycleService, startInitialPrompt] in
                // Linked before the prompt is dispatched, not after: this route links regardless
                // of `automaticallyLinkPullRequests`, and doing it first means transcript
                // detection finds the pull request already linked and asks no redundant
                // "link this?" question under the prompt. Best-effort — a GitHub hiccup must not
                // stop a review from starting.
                _ = try? await linkService.link(
                    identifier,
                    owner: .thread(threadID),
                    detail: knownDetail
                )

                // Re-resolved after the await rather than carried across it.
                guard let liveThread = lifecycleService.modelContext.resolveThread(id: threadID),
                      let conversation = liveThread.soleMainConversation else {
                    throw StartError.conversationMissing
                }
                // Deliberately short. The instructions are not inlined here — the agent fetches
                // them with `get_pr_review_instructions`, exactly as it does when the user asks
                // for a review in a thread that already exists, so both routes run one shared
                // path and show the same card.
                startInitialPrompt(conversation, Self.reviewRequestPrompt(url: url))
            }
        )
    }

    /// Reads like something the user would type, because that is what it stands in for. The URL
    /// alone names the pull request — `get_pr_review_instructions` fetches the title itself, so
    /// repeating the shorthand or title here would only pad the bubble.
    static func reviewRequestPrompt(url: URL) -> String {
        "Review pull request: \(url.absoluteString)"
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
    /// typed thread would get, because refusing to start the review would leave the user with an
    /// error and no way to see why from the footer. Only "nothing can run at all" is an error,
    /// and that is caught before this runs.
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

    /// The pinned provider only applies while it is actually ready; otherwise the review follows
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

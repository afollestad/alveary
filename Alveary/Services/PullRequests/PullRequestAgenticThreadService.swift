import AgentCLIKit
import Foundation
import SwiftData

/// What `start` hands back. The conversation is answered as soon as the thread exists so the
/// caller can mark the route working against a real thread; everything that still has to happen
/// rides `dispatch`.
///
/// Deliberately a plain value rather than a nested type, so the pane's view model can name it
/// without reaching for the service.
struct PullRequestAgenticThreadStart {
    /// The new thread's sole-main-conversation id, which is what the caller tracks activity by.
    let conversationID: String
    /// Links the pull request, settles the checkout when one is owed, then dispatches the first
    /// prompt — in that order, behind `start`'s return. Await it only to surface a failure;
    /// nothing else may depend on it.
    let dispatch: Task<PullRequestAgenticDispatchOutcome, Error>
}

/// What the deferred half reports back. A *thrown* `dispatch` means the prompt never went out, so
/// the caller ends the route; this value means it did, and carries anything non-fatal that went
/// wrong on the way.
///
/// `linkFailure` is a value rather than a thrown error precisely because linking is best-effort:
/// throwing it would tell the caller the run had died when the agent is in fact working.
struct PullRequestAgenticDispatchOutcome: Equatable {
    /// A failed link, already localized, for the caller's toast. Nil when the link landed.
    let linkFailure: String?
}

/// Starts the agentic threads the pull request pane's footer offers: a Task thread whose first
/// prompt asks for the work the way the user would. The agent picks the workflow up from the
/// `alveary_host` tools — an instructions tool first, and the matching writer last.
///
/// The two kinds differ in four places and nowhere else: the thread's name, its first prompt,
/// whether it needs a checkout — which is also what lets `.addressFeedback` refuse when no
/// checkout is possible — and which sidebar section it lands in. Everything below — seed
/// resolution and its degrade-never-refuse rules, answering as soon as the thread exists,
/// link-then-dispatch ordering — is shared, which is why a second caller uses this service
/// rather than copying it.
@MainActor
final class PullRequestAgenticThreadService {
    /// Which half of a pull request's life the thread is for.
    enum Kind: Hashable, CaseIterable {
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

        /// Each route has its own section setting — a review thread and a feedback thread are
        /// different work — unlike the provider, model, and effort they share.
        func sectionID(in settings: AppSettings) -> String? {
            switch self {
            case .review:
                settings.pullRequestReviewSectionID
            case .addressFeedback:
                settings.pullRequestAddressFeedbackSectionID
            }
        }
    }

    enum StartError: LocalizedError, Equatable {
        case noReadyProvider
        case conversationMissing
        /// Addressing feedback edits and pushes, so it needs a checkout — and with no project for
        /// the repository and nothing to borrow, the ladder has nowhere to cut one. The one case
        /// here the caller renders as a modal rather than the footer's banner.
        case projectMissing(repository: String)

        var errorDescription: String? {
            switch self {
            case .noReadyProvider:
                return "No agent is ready to start this thread. Check the Agents settings."
            case .conversationMissing:
                return "The thread could not be started."
            case .projectMissing(let repository):
                return "\(repository) is not added as a project. Add it and try again."
            }
        }
    }

    /// Everything the deferred half needs, snapshotted before its task suspends — models cannot
    /// cross that boundary, and a wide argument list of the same fields could not either.
    struct DeferredWork {
        let kind: Kind
        let identifier: PullRequestIdentifier
        let url: URL
        let threadID: PersistentIdentifier
        let threadName: String
        let trustedDetail: PullRequestDetail?
        let trustedSummary: PullRequestSummary?
        /// The provisional borrow `start` seeded the thread with, still to be branch-verified.
        let seededBorrow: TaskWorkspaceDescriptor?
        let preferredProjectID: PersistentIdentifier?
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
    /// The branch checked out at a path, or nil when it cannot be read. A closure rather than
    /// `GitService`, whose 38 members would dwarf a test stub for this one probe — the same seam
    /// `directoryExists` already is.
    let currentBranch: @MainActor (String) async -> String?
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
        currentBranch: @escaping @MainActor (String) async -> String? = { _ in nil },
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
        self.currentBranch = currentBranch
        self.startInitialPrompt = startInitialPrompt
    }

    /// Creates the thread and answers the moment it exists, so the caller's spinner is backed by a
    /// real thread as early as possible. Linking, settling the checkout, and the first prompt run
    /// behind that on the returned `dispatch`.
    ///
    /// `knownDetail` lets a caller that already fetched this pull request — the pane always has —
    /// spare the link its own round trip, and hands the checkout ladder the head branch without
    /// one either. `knownSummary` is the same handover one rung down, for a pane opened from a
    /// list row whose detail has not landed; together they are what make the link reliable rather
    /// than merely best-effort, because neither needs the network.
    func start(
        kind: Kind,
        identifier: PullRequestIdentifier,
        url: URL,
        knownDetail: PullRequestDetail? = nil,
        knownSummary: PullRequestSummary? = nil,
        preferredProjectID: PersistentIdentifier? = nil
    ) async throws -> PullRequestAgenticThreadStart {
        let settings = settingsService.current
        let threadName = kind.threadName(for: identifier)
        // The link ignores a detail naming a different pull request and fetches its own; the
        // ladder must not trust one either, or the checkout lands on that other pull request's
        // head branch.
        let trustedDetail = knownDetail?.id == identifier ? knownDetail : nil
        let trustedSummary = knownSummary?.id == identifier ? knownSummary : nil
        // Only the rungs that are pure local reads run here; cutting a worktree is a fetch plus a
        // git command, so it rides `dispatch`. This borrow is provisional — the deferred half
        // verifies the branch it is actually on before keeping it.
        let borrowed = kind.needsCheckout
            ? borrowedWorkspace(identifier: identifier, headRefName: trustedDetail?.headRefName)
            : nil
        // Ahead of `resolvedSeedSettings`, which is the one suspension here and can cost seconds
        // on a cold provider-discovery cache: this refusal is a pure local read, and making the
        // user watch a spinner before it lands would be a lie about what the click was doing.
        if kind.needsCheckout,
           borrowed == nil,
           resolvedProject(for: identifier, preferredProjectID: preferredProjectID) == nil {
            throw StartError.projectMissing(repository: identifier.nameWithOwner)
        }
        let seed = try await resolvedSeedSettings(settings: settings)

        let thread = try lifecycleService.insertTaskThread(
            seed: Self.threadSeed(
                seed,
                name: threadName,
                workspace: borrowed,
                placement: resolvedPlacement(for: kind, settings: settings)
            )
        )
        guard let conversation = thread.soleMainConversation else {
            throw StartError.conversationMissing
        }
        // Snapshotted before the dispatch task, which suspends and can invalidate the models.
        let work = DeferredWork(
            kind: kind,
            identifier: identifier,
            url: url,
            threadID: thread.persistentModelID,
            threadName: threadName,
            trustedDetail: trustedDetail,
            trustedSummary: trustedSummary,
            seededBorrow: borrowed,
            preferredProjectID: preferredProjectID
        )
        return PullRequestAgenticThreadStart(
            conversationID: conversation.id,
            // `self` is captured on purpose: settling the checkout needs the service's own
            // collaborators, and this service is app-scoped, so the task cannot outlive it.
            dispatch: Task { @MainActor [self] in
                try await runDeferredWork(work)
            }
        )
    }

    /// Links the pull request, settles the checkout, and sends the first prompt — in that order,
    /// behind `start`'s return.
    private func runDeferredWork(_ work: DeferredWork) async throws -> PullRequestAgenticDispatchOutcome {
        // Fetched for every checkout route now, not only the ones still owed a workspace:
        // verifying a borrow needs the head branch just as much as cutting a worktree does.
        let detail = await resolvedDetail(
            knownDetail: work.trustedDetail,
            identifier: work.identifier,
            fetchWhenMissing: work.kind.needsCheckout
        )
        // Linked before the prompt is dispatched, not after: this route links regardless of
        // `automaticallyLinkPullRequests`, and doing it first means transcript detection finds the
        // pull request already linked and asks no redundant "link this?" question under the
        // prompt. Non-fatal — a GitHub hiccup must not stop a thread from starting — but reported
        // rather than swallowed.
        var linkFailure: String?
        do {
            _ = try await linkService.link(
                work.identifier,
                owner: .thread(work.threadID),
                detail: detail,
                summary: work.trustedSummary
            )
        } catch {
            linkFailure = error.localizedDescription
        }
        if work.kind.needsCheckout {
            await settleCheckout(work, headRefName: detail?.headRefName)
        }

        // Re-resolved after the await rather than carried across it.
        guard let liveThread = lifecycleService.modelContext.resolveThread(id: work.threadID),
              let conversation = liveThread.soleMainConversation else {
            throw StartError.conversationMissing
        }
        // Deliberately short. The instructions are not inlined here — the agent fetches them with
        // the matching instructions tool, exactly as it does when the user asks for the same work
        // in a thread that already exists, so both routes run one shared path and show the same
        // card.
        startInitialPrompt(conversation, work.kind.requestPrompt(url: work.url))
        return PullRequestAgenticDispatchOutcome(linkFailure: linkFailure)
    }

    /// The workspace's own root is the only grant either kind needs: a review reaches GitHub
    /// through host tools, and addressing feedback works inside its checkout.
    private static func threadSeed(
        _ seed: SeedSettings,
        name: String,
        workspace: TaskWorkspaceDescriptor?,
        placement: TaskThreadSidebarPlacement
    ) -> TaskThreadSeed {
        TaskThreadSeed(
            provider: seed.provider,
            permissionMode: seed.permissionMode,
            model: seed.model,
            effort: seed.effort,
            isDraft: false,
            name: name,
            grantedRoots: [],
            workspace: workspace,
            placement: placement
        )
    }

    /// Resolved here rather than left to the seed because `insertTaskThread` *throws* on a
    /// section that has gone — right for a user who just named one and can retry, wrong for a
    /// footer button with nowhere to explain a refusal. `AppSettings` stores a bare id with no
    /// relationship nullifying it, so a removed section — or an id naming a builtin row, which
    /// `Pinned` and `Projects` must never accept — is the ordinary case rather than a corruption;
    /// it degrades to `Tasks` like every other seed setting here.
    ///
    /// Never `.project`: a `.review` thread is project-less by design, and an `.addressFeedback`
    /// thread carries its checkout in the workspace descriptor, so both stay projectless — which
    /// is exactly what makes a custom section render for them.
    private func resolvedPlacement(for kind: Kind, settings: AppSettings) -> TaskThreadSidebarPlacement {
        guard let sectionID = kind.sectionID(in: settings),
              let section = lifecycleService.modelContext.resolveSidebarSection(id: sectionID),
              section.kind == .custom else {
            return .tasks
        }
        return .section(id: section.id)
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

import Foundation
import Observation

enum PullRequestsUnavailableReason: Equatable {
    case notInstalled
    case notAuthenticated
    case rateLimited
    case failed(String)
}

enum PullRequestsLoadPhase: Equatable {
    case idle
    case loading
    case loaded
    case unavailable(PullRequestsUnavailableReason)
}

@MainActor
@Observable
final class PullRequestsViewModel {
    static let refreshInterval: TimeInterval = 60

    // Internal (not private) so the review-batch companion can reach the service.
    let service: any PullRequestsService
    let avatarLoader: GitHubAvatarLoader
    private let listCache: PullRequestsListCache?
    // Internal (not private) so the filtering companion can persist filter changes.
    let settingsService: (any SettingsService)?
    private let now: () -> Date
    /// Internal so the attachments companion can upload; optional because tests
    /// and previews construct the view model without an uploader.
    let attachmentUploadService: (any GitHubAttachmentUploadService)?
    /// Seeds a successful upload's local bytes into the app's image caches so
    /// the reference renders immediately — GitHub keeps fresh attachment assets
    /// session-gated, so refetching the uploaded URL can 404 for a while.
    let attachmentImageSeeder: (@MainActor (GitHubAttachmentUpload) async -> Void)?
    /// Notes the opened pane's repository as a render context for resolving
    /// signed attachment-image URLs (see `GitHubAttachmentImageURLResolver`).
    let attachmentImageRepositoryRegistrar: (@MainActor (String) -> Void)?
    /// App-level toast presentation. Attachment failures surface here rather than
    /// in a pane banner, because the pane may already be closed when one lands.
    let presentToast: @MainActor @Sendable (String) -> Void

    private var hasLoadedListCache = false

    // Contextual-pane session state; lifecycle in the Pane Sessions extension below.
    private(set) var activePaneTarget: PullRequestPaneTarget?
    /// The surface that opened `activePaneTarget`; the root filters on it so a
    /// pane cannot render outside the context it was opened from.
    private(set) var activePaneOrigin: PullRequestPaneOrigin = .screen
    private(set) var paneSessions: [PullRequestPaneTarget: PullRequestPaneSession] = [:]
    /// The open pane's summary status, mirrored out of `paneSessions` so the app root can
    /// follow it without observing the whole dictionary — `@Observable` has no per-key
    /// granularity, so reading a session there made every session write (typing, collapsing
    /// a file, a diff landing) re-render the root and the mounted thread view. Every
    /// mutation of `paneSessions` or `activePaneTarget` in this file ends with
    /// `refreshActivePaneSummaryStatus()`; the dictionary's setter is private to it.
    private(set) var activePaneSummaryStatus: PullRequestStatus?
    private(set) var pendingPaneDismissals: Set<PaneSessionDismissalRequest<PullRequestPaneTarget>> = []
    private var deactivatedPaneDismissals: Set<PaneSessionDismissalRequest<PullRequestPaneTarget>> = []

    private(set) var loadPhase: PullRequestsLoadPhase = .idle
    private(set) var items: [PullRequestSummary] = []
    /// Non-fatal fetch warnings, such as SAML-protected organizations withholding results.
    private(set) var warnings: [String] = []
    /// A refresh failure while stale rows remain visible; unavailability replaces the list instead.
    private(set) var errorMessage: String?
    private(set) var isRefreshing = false
    private(set) var lastRefreshedAt: Date?

    /// The open comment-composing session's BlockInputKit store; created by the
    /// composer-opening methods and cleared on cancel or successful save.
    var composerDraft: PullRequestCommentDraftBox?

    /// Attachment uploads currently running, by destination editor. View-model
    /// scoped (not session scoped) so an upload survives closing the pane, and
    /// mutated by `PullRequestsViewModel+Attachments.swift`.
    var attachmentUploadsInFlight: Set<PullRequestAttachmentDestination> = []

    /// The in-flight "open a pending review" call per pull request. GitHub allows
    /// one pending review per viewer, so comments saved in quick succession share
    /// this task instead of each creating their own. Mutated by
    /// `PullRequestsViewModel+PendingComments.swift`.
    @ObservationIgnored
    var pendingReviewCreationTasks: [PullRequestPaneTarget: Task<String, Error>] = [:]

    /// In-flight detail and diff loads per pane target. Only the pane the user is
    /// looking at keeps its loads; opening another target cancels the rest, which
    /// is what bounds concurrent `gh` invocations. Mutated by
    /// `PullRequestsViewModel+PaneLoading.swift`.
    @ObservationIgnored
    var paneLoadTasks: [PullRequestPaneTarget: PullRequestPaneLoadTasks] = [:]

    /// A failed upload waiting on browser-session access; non-nil presents the
    /// Full Disk Access guidance sheet. Mutated by the attachments companion.
    var attachmentAccessRequest: PullRequestAttachmentAccessRequest?

    /// Memoized list shaping, owned by `PullRequestsViewModel+Filtering.swift`.
    /// `@ObservationIgnored` so filling it during a render publishes nothing.
    @ObservationIgnored
    var visibleListCache: VisibleListCache?

    var searchQuery = ""
    /// Empty sets mean "no constraint" — every status / repository passes.
    var selectedStatuses: Set<PullRequestStatus> = []
    var selectedRepositories: Set<String> = []
    /// The active tab; restored from settings and persisted through `selectFilter(_:)`.
    private(set) var selectedFilter = PullRequestsFilter.all

    /// Reference date for relative-age labels; injectable so snapshots stay deterministic.
    ///
    /// Stored rather than read from `now()` per access: every row carries it, so a fresh
    /// `Date` per read makes every row's inputs differ on every render pass and defeats
    /// SwiftUI's diffing. `touchReferenceDate()` advances it.
    private(set) var referenceDate: Date

    init(
        service: any PullRequestsService,
        avatarLoader: GitHubAvatarLoader,
        listCache: PullRequestsListCache? = nil,
        settingsService: (any SettingsService)? = nil,
        attachmentUploadService: (any GitHubAttachmentUploadService)? = nil,
        attachmentImageSeeder: (@MainActor (GitHubAttachmentUpload) async -> Void)? = nil,
        attachmentImageRepositoryRegistrar: (@MainActor (String) -> Void)? = nil,
        presentToast: @escaping @MainActor @Sendable (String) -> Void = { _ in },
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.avatarLoader = avatarLoader
        self.listCache = listCache
        self.settingsService = settingsService
        self.attachmentUploadService = attachmentUploadService
        self.attachmentImageSeeder = attachmentImageSeeder
        self.attachmentImageRepositoryRegistrar = attachmentImageRepositoryRegistrar
        self.presentToast = presentToast
        self.now = now
        self.referenceDate = now()
        if let settings = settingsService?.current {
            selectedFilter = PullRequestsFilter(rawValue: settings.pullRequestsSelectedTab) ?? .all
            selectedStatuses = settings.pullRequestsStatusFilters
            selectedRepositories = settings.pullRequestsRepositoryFilters
        }
    }

    /// Switches the visible tab and persists it as the next launch's initial tab.
    func selectFilter(_ filter: PullRequestsFilter) {
        guard selectedFilter != filter else {
            return
        }
        selectedFilter = filter
        settingsService?.update { $0.pullRequestsSelectedTab = filter.rawValue }
    }

    // MARK: - Refresh

    /// Screen-appearance refresh: paints the persisted last list immediately, then
    /// refreshes over the network, throttled so tab flips do not hammer GitHub.
    func refreshForScreen() async {
        await loadCachedListIfNeeded()
        if let lastRefreshedAt, now().timeIntervalSince(lastRefreshedAt) < Self.refreshInterval {
            return
        }
        await refresh()
    }

    /// Spawns an unthrottled refresh; for the header's explicit refresh action.
    func requestRefresh() {
        Task {
            await refresh()
        }
    }

    /// Fetches all three involvement buckets in one batched request, so every tab
    /// settles in a single UI invalidation.
    func refresh() async {
        guard !isRefreshing else {
            return
        }
        isRefreshing = true
        if items.isEmpty {
            loadPhase = .loading
        }
        defer {
            isRefreshing = false
        }
        do {
            let result = try await service.listInvolvedPullRequests()
            items = result.summaries
            warnings = result.warnings
            errorMessage = nil
            lastRefreshedAt = now()
            touchReferenceDate()
            loadPhase = .loaded
            normalizeRepositoryFilter()
            saveListCache()
        } catch is CancellationError {
            // Leaving the screen cancels the load; that is not an error worth a banner.
        } catch let error as PullRequestsServiceError {
            guard !Task.isCancelled else {
                // Shell teardown wraps cancellation in service errors; same non-error.
                return
            }
            applyFailure(error)
        } catch {
            guard !Task.isCancelled else {
                return
            }
            applyFailure(.transport(error.localizedDescription))
        }
    }

    /// Applies a locally-known status to a list row, so closing or reopening a
    /// pull request updates its glyph before the next list fetch confirms it.
    func applyStatus(_ status: PullRequestStatus, toRow id: PullRequestIdentifier) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        items[index].status = status
    }

    /// Advances the clock relative ages are measured against. Guarded on equality so an
    /// injected fixed clock publishes nothing and snapshot renders stay still. Called
    /// whenever new data lands, plus on the list's own slow tick so ages keep moving on
    /// a screen nobody is touching.
    func touchReferenceDate() {
        let value = now()
        guard value != referenceDate else {
            return
        }
        referenceDate = value
    }

    func retry() {
        loadPhase = .idle
        requestRefresh()
    }

    func clearError() {
        errorMessage = nil
    }

    func dismissWarnings() {
        warnings = []
    }

    // MARK: - Private

    private func applyFailure(_ error: PullRequestsServiceError) {
        if items.isEmpty {
            loadPhase = .unavailable(Self.unavailableReason(for: error))
        } else {
            // Keep the stale rows visible and say why the refresh failed.
            errorMessage = error.localizedDescription
        }
    }

    /// Paints the persisted last list once per app run, so the screen shows the
    /// previous rows instantly while the network refresh runs behind it.
    private func loadCachedListIfNeeded() async {
        guard !hasLoadedListCache else {
            return
        }
        hasLoadedListCache = true
        guard items.isEmpty, let listCache, let cached = await listCache.load() else {
            return
        }
        // A refresh may have landed while the cache read was in flight.
        guard items.isEmpty else {
            return
        }
        items = cached
        touchReferenceDate()
        loadPhase = .loaded
        normalizeRepositoryFilter()
    }

    private func saveListCache() {
        guard let listCache else {
            return
        }
        let snapshot = items
        Task.detached {
            await listCache.save(snapshot)
        }
    }

    private static func unavailableReason(for error: PullRequestsServiceError) -> PullRequestsUnavailableReason {
        switch error {
        case .ghNotInstalled:
            return .notInstalled
        case .notAuthenticated:
            return .notAuthenticated
        case .rateLimited:
            return .rateLimited
        case .requestFailed, .responseTooLarge, .decodingFailed, .transport:
            return .failed(error.localizedDescription)
        }
    }

}

// MARK: - Pane Sessions

extension PullRequestsViewModel {
    func requestDetails(_ summary: PullRequestSummary, origin: PullRequestPaneOrigin = .screen) {
        openPane(target: .details(summary.id), summary: summary, origin: origin)
    }

    /// Opens a pull request the caller has no summary for — a transcript's unlink card names
    /// one that is deliberately not linked, so no stored snapshot exists to open it with.
    ///
    /// A listed row already carries a usable summary; otherwise the pane opens without one and
    /// its own `loadDetail` backfills it, so the wait and any failure render in the pane rather
    /// than blocking the open behind a `fetchDetail`.
    func requestDetails(_ identifier: PullRequestIdentifier, origin: PullRequestPaneOrigin) {
        guard let summary = items.first(where: { $0.id == identifier }) else {
            openPane(target: .details(identifier), summary: nil, origin: origin)
            return
        }
        requestDetails(summary, origin: origin)
    }

    private func openPane(
        target: PullRequestPaneTarget,
        summary: PullRequestSummary?,
        origin: PullRequestPaneOrigin
    ) {
        // The pane's repository is a candidate context for signed attachment
        // image URLs; register before its markdown can render.
        attachmentImageRepositoryRegistrar?(target.identifier.nameWithOwner)
        if let request = pendingPaneDismissals.first(where: { $0.target == target }) {
            deactivatedPaneDismissals.remove(request)
            dismissPane(target, generation: request.generation, restoreFocus: false)
        }
        // Only the pane being opened keeps its loads; everything else is superseded
        // work whose `gh` subprocesses would otherwise run to completion unread.
        cancelPaneLoads(except: target)
        if paneSessions[target] == nil {
            let session = PullRequestPaneSession(generation: UUID(), summary: summary)
            paneSessions[target] = session
            loadPaneContent(target: target, generation: session.generation)
        } else {
            if let summary, paneSessions[target]?.summary == nil {
                // An identifier-opened session still waiting on its detail; a caller
                // holding a snapshot can fill the header now rather than after the fetch.
                paneSessions[target]?.summary = summary
            }
            // Reopening a pane whose loads were cancelled on the way out; without this
            // the retained session would render its spinner forever.
            if let generation = paneSessions[target]?.generation {
                resumeIncompleteLoads(target: target, generation: generation)
            }
        }
        activePaneTarget = target
        activePaneOrigin = origin
        refreshActivePaneSummaryStatus()
    }

    /// Re-derives the mirrored status; guarded on equality so the writes that cannot
    /// affect it publish nothing.
    private func refreshActivePaneSummaryStatus() {
        let status = activePaneTarget.flatMap { paneSessions[$0]?.summary?.status }
        guard status != activePaneSummaryStatus else {
            return
        }
        activePaneSummaryStatus = status
    }

    /// The active target, but only when its origin matches the surface asking.
    /// The root builds `RightPaneContextualTargets` through this so a shared
    /// pane lane cannot show one context's pull request inside another.
    func activePaneTarget(for origin: PullRequestPaneOrigin) -> PullRequestPaneTarget? {
        guard activePaneOrigin == origin else {
            return nil
        }
        return activePaneTarget
    }

    func isDetailActive(_ id: PullRequestIdentifier) -> Bool {
        activePaneTarget == .details(id)
    }

    /// The open detail's identifier, for surfaces that highlight one row out of many.
    /// Handing rows this value rather than an `isDetailActive` closure lets them compare
    /// equal across a render pass, so a selection change repaints two rows instead of all
    /// of them. Reading it still registers the dependency on `activePaneTarget`.
    var activeDetailIdentifier: PullRequestIdentifier? {
        guard case .details(let id) = activePaneTarget else {
            return nil
        }
        return id
    }

    /// Route-only deactivation; preserves the session for another root pane.
    func deactivatePane() {
        activePaneTarget = nil
        refreshActivePaneSummaryStatus()
    }

    /// Phase one of closing: schedules the captured session for discard after the slide-out.
    func deactivatePane(_ target: PullRequestPaneTarget, generation: UUID) {
        guard activePaneTarget == target,
              paneSessions[target]?.generation == generation else {
            return
        }
        let request = PaneSessionDismissalRequest(target: target, generation: generation)
        pendingPaneDismissals.insert(request)
        deactivatedPaneDismissals.insert(request)
        // The session is already scheduled for discard, so stop its subprocesses at
        // the start of the slide-out rather than after it.
        cancelPaneLoads(for: target)
        activePaneTarget = nil
        refreshActivePaneSummaryStatus()
    }

    func dismissPane(
        _ target: PullRequestPaneTarget,
        generation: UUID,
        restoreFocus: Bool = true
    ) {
        let request = PaneSessionDismissalRequest(target: target, generation: generation)
        guard paneSessions[target]?.generation == generation else {
            pendingPaneDismissals.remove(request)
            deactivatedPaneDismissals.remove(request)
            return
        }
        pendingPaneDismissals.remove(request)
        deactivatedPaneDismissals.remove(request)
        cancelPaneLoads(for: target)
        paneSessions[target] = nil
        if activePaneTarget == target {
            activePaneTarget = nil
        }
        refreshActivePaneSummaryStatus()
    }

    // MARK: - Diff shaping

    func showMoreDiffFiles() {
        guard let target = activePaneTarget,
              var session = paneSessions[target],
              let files = session.diffFiles else {
            return
        }
        session.renderedDiffFileCount = PullRequestDiffFilePaging.nextRenderedFileCount(
            current: session.renderedDiffFileCount,
            total: files.count
        )
        paneSessions[target] = session
        refreshActivePaneSummaryStatus()
    }

    func toggleDiffFileCollapse(_ fileID: String) {
        guard let target = activePaneTarget,
              var session = paneSessions[target] else {
            return
        }
        if session.collapsedDiffFileIDs.contains(fileID) {
            session.collapsedDiffFileIDs.remove(fileID)
        } else {
            session.collapsedDiffFileIDs.insert(fileID)
        }
        paneSessions[target] = session
        refreshActivePaneSummaryStatus()
    }

    func mutateActiveSession(_ mutate: (inout PullRequestPaneSession) -> Void) {
        guard let target = activePaneTarget, var session = paneSessions[target] else {
            return
        }
        mutate(&session)
        paneSessions[target] = session
        refreshActivePaneSummaryStatus()
    }

    /// Generation-guarded session write for async completions; returns whether the
    /// session was still live.
    @discardableResult
    func updateSession(
        _ target: PullRequestPaneTarget,
        generation: UUID,
        _ mutate: (inout PullRequestPaneSession) -> Void
    ) -> Bool {
        guard var session = paneSessions[target], session.generation == generation else {
            return false
        }
        mutate(&session)
        paneSessions[target] = session
        refreshActivePaneSummaryStatus()
        return true
    }

}

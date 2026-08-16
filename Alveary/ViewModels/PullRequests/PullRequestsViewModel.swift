import Foundation
import Observation

@MainActor
@Observable
final class PullRequestsViewModel {
    static let refreshInterval: TimeInterval = 60
    /// Rows fetched per involvement bucket, for the first page and every "Load more" after it.
    static let listPageSize = 50

    // Internal (not private) so the review-batch companion can reach the service.
    let service: any PullRequestsService
    let avatarLoader: GitHubAvatarLoader
    // Internal (not private) so the loading companion can paint and persist buckets.
    let listCache: PullRequestsListCache?
    // Internal (not private) so the filtering companion can persist filter changes.
    let settingsService: (any SettingsService)?
    // Internal (not private) so the loading companion can stamp bucket fetch times.
    let now: () -> Date
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
    /// App-level toast presentation, for failures a pane banner cannot carry because the pane may
    /// already be closed when one lands: attachment uploads and an agentic thread's deferred dispatch.
    let presentToast: @MainActor @Sendable (String) -> Void
    /// Spawns the footer's agentic thread — review or address-feedback — and answers as soon as
    /// it exists. A closure rather than the service so tests and previews stay light; nil means
    /// the footer's agentic options do nothing.
    let agenticThreadStarter: (
        @MainActor (PullRequestAgenticThreadRequest) async throws -> PullRequestAgenticThreadStart
    )?
    /// Resolves the pane's attached review proposal and owns the envelope it renders from.
    /// This is not the `ModelContext` this view model deliberately does without — the
    /// coordinator holds its own private context; the view model still holds none. Optional
    /// because tests and previews construct the view model without one, which simply leaves
    /// every pane unattached. See `PullRequestsViewModel+ReviewProposalAttachment.swift`.
    let reviewProposalCoordinator: PullRequestReviewProposalCoordinator?

    /// The bus a pull request Alveary changed elsewhere announces itself on; see
    /// `PullRequestsViewModel+RemoteChanges.swift`. Injectable so a test suite gets its own.
    @ObservationIgnored let notificationCenter: NotificationCenter
    /// How long an announcement waits before its refetch, coalescing the burst one agent turn can
    /// produce. Injectable so tests need not sleep.
    @ObservationIgnored let remoteRefreshDelay: Duration
    /// How long the search field waits after a keystroke before the list reshapes. `.zero`
    /// commits synchronously with no `Task` hop, which is what lets tests and snapshot fixtures
    /// set `searchQuery` and read the narrowed list in the same turn.
    @ObservationIgnored let searchDebounce: Duration
    @ObservationIgnored var remoteChangeObserver: (any NSObjectProtocol)?
    /// Debounced detail refetches, keyed by the target whose session they refresh.
    @ObservationIgnored var remoteRefreshTasks: [PullRequestPaneTarget: Task<Void, Never>] = [:]
    @ObservationIgnored var remoteListRefreshTask: Task<Void, Never>?

    @ObservationIgnored var hasLoadedListCache = false

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

    /// What each involvement bucket last returned. Fetching is bucket-demand-driven — a tab loads
    /// only the buckets it renders — so these are stored separately rather than as one list, which
    /// is what lets a tab reuse a bucket another tab already paid for. Mutated by
    /// `PullRequestsViewModel+Loading.swift`.
    var bucketStates: [PullRequestInvolvementBucket: PullRequestBucketState] = [:]
    /// Buckets with a request outstanding. `isRefreshing` derives from this, so it stays observable.
    var inFlightBuckets: Set<PullRequestInvolvementBucket> = []
    /// The last failure per bucket, which is what makes a tab whose buckets all failed unavailable
    /// while a tab sharing one healthy bucket still renders.
    var bucketFailures: [PullRequestInvolvementBucket: PullRequestsServiceError] = [:]
    /// The loaded buckets merged into one list; rebuilt from `bucketStates` on every change.
    private(set) var items: [PullRequestSummary] = []
    /// Non-fatal fetch warnings, such as SAML-protected organizations withholding results.
    var warnings: [String] = []
    /// A refresh failure while stale rows remain visible; unavailability replaces the list instead.
    var errorMessage: String?
    /// A "Load more" page in flight. Stored rather than derived from `inFlightBuckets`, which a
    /// concurrent page-one refresh also fills — only the footer's own request may disable it.
    var isLoadingMore = false

    var isRefreshing: Bool {
        !inFlightBuckets.isEmpty
    }

    /// Newest bucket fetch, so a screen appearance can tell a cold start from a warm one.
    var lastRefreshedAt: Date? {
        bucketStates.values.map(\.fetchedAt).max()
    }

    /// The visible tab's phase; the screen renders one tab, so this is what it switches on.
    var loadPhase: PullRequestsLoadPhase {
        loadPhase(for: selectedFilter)
    }

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

    /// Memoized list shaping per tab, owned by `PullRequestsViewModel+Filtering.swift`.
    /// One entry per tab rather than one overall, so alternating tabs hits instead of
    /// recomputing each way. `@ObservationIgnored` so filling it during a render publishes
    /// nothing. Entries for tabs the user is not looking at self-invalidate on their key.
    @ObservationIgnored
    var visibleListCaches: [PullRequestsFilter: VisibleListCache] = [:]

    // Search state; the field/list split and the debounce live in the filtering companion, so
    // these are internal rather than private.
    var typedSearchQuery = ""
    /// The committed query, already trimmed, that every filtering path reads. Written only by
    /// `commitSearchQuery()`.
    var activeSearchQuery = ""
    @ObservationIgnored var searchCommitTask: Task<Void, Never>?
    /// Bumped per keystroke so a debounce that already slept past its cancellation check still
    /// declines to commit a query the user has moved on from.
    @ObservationIgnored var searchCommitGeneration = 0
    /// Single-select, and pushed into the GitHub search rather than only applied here — see
    /// `PullRequestStatusFilter`. Changing it invalidates every bucket. Mutated through
    /// `selectStatusFilter(_:)` in the filtering companion.
    private(set) var selectedStatusFilter: PullRequestStatusFilter = .open
    /// An empty set means "no constraint" — every repository passes.
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
        agenticThreadStarter: (
            @MainActor (PullRequestAgenticThreadRequest) async throws -> PullRequestAgenticThreadStart
        )? = nil,
        reviewProposalCoordinator: PullRequestReviewProposalCoordinator? = nil,
        notificationCenter: NotificationCenter = .default,
        remoteRefreshDelay: Duration = .milliseconds(750),
        searchDebounce: Duration = .milliseconds(200),
        now: @escaping () -> Date = Date.init
    ) {
        self.notificationCenter = notificationCenter
        self.remoteRefreshDelay = remoteRefreshDelay
        self.searchDebounce = searchDebounce
        self.service = service
        self.avatarLoader = avatarLoader
        self.listCache = listCache
        self.settingsService = settingsService
        self.attachmentUploadService = attachmentUploadService
        self.attachmentImageSeeder = attachmentImageSeeder
        self.attachmentImageRepositoryRegistrar = attachmentImageRepositoryRegistrar
        self.presentToast = presentToast
        self.agenticThreadStarter = agenticThreadStarter
        self.reviewProposalCoordinator = reviewProposalCoordinator
        self.now = now
        self.referenceDate = now()
        if let settings = settingsService?.current {
            selectedFilter = PullRequestsFilter(rawValue: settings.pullRequestsSelectedTab) ?? .all
            selectedStatusFilter = settings.pullRequestsStatusFilter
            selectedRepositories = settings.pullRequestsRepositoryFilters
        }
        observeRemoteChanges()
    }

    deinit {
        MainActor.assumeIsolated {
            searchCommitTask?.cancel()
            endRemoteChangeObservation()
        }
    }

    /// Switches the visible tab, persists it as the next launch's initial tab, and loads whatever
    /// buckets the new tab still needs — nothing is fetched for a tab until it is shown.
    func selectFilter(_ filter: PullRequestsFilter) {
        guard selectedFilter != filter else {
            return
        }
        selectedFilter = filter
        settingsService?.update { $0.pullRequestsSelectedTab = filter.rawValue }
        Task {
            await loadIfNeeded(for: filter)
        }
    }

    /// Applies a locally-known status to a list row, so closing or reopening a
    /// pull request updates its glyph before the next list fetch confirms it.
    ///
    /// Writes through every bucket holding the row rather than `items`, which is derived.
    func applyStatus(_ status: PullRequestStatus, toRow id: PullRequestIdentifier) {
        var didChange = false
        for (bucket, state) in bucketStates {
            guard let index = state.summaries.firstIndex(where: { $0.id == id }) else {
                continue
            }
            bucketStates[bucket]?.summaries[index].status = status
            didChange = true
        }
        guard didChange else {
            return
        }
        rebuildItems()
    }

    /// Re-derives `items` from the loaded buckets. `items` keeps a private setter because this is
    /// the only way it may change — every write goes through `bucketStates` first.
    ///
    /// Also the one seam where avatars are prefetched, since it is the only place the row set can
    /// change: warming here means the first flick through a freshly loaded list draws avatars
    /// rather than letter placeholders, and rows already holding a cached URL are skipped.
    func rebuildItems() {
        items = PullRequestListMerge.merge(
            PullRequestInvolvementBucket.allCases.compactMap { bucketStates[$0]?.summaries }
        )
        avatarLoader.prefetch(items.compactMap(\.authorAvatarURL))
    }

    /// Narrows every bucket's GitHub search to one status, persisting it as the next launch's
    /// selection. Every loaded bucket answered the previous search, so all of them are marked
    /// stale: the visible tab reloads immediately and the rest reload when next shown.
    ///
    /// The rows themselves stay — the client-side status filter narrows them on the spot, so a
    /// narrowing change is correct before the reload lands and a widening one merely reads empty
    /// for a moment rather than blanking a list that was showing the right thing.
    func selectStatusFilter(_ filter: PullRequestStatusFilter) {
        guard selectedStatusFilter != filter else {
            return
        }
        selectedStatusFilter = filter
        settingsService?.update { $0.pullRequestsStatusFilter = filter }
        markAllBucketsStale()
        // A failure under the previous search says nothing about this one.
        bucketFailures = [:]
        errorMessage = nil
        Task {
            await loadIfNeeded(for: selectedFilter)
        }
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

    func clearError() {
        errorMessage = nil
    }

    func dismissWarnings() {
        warnings = []
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
            // A retained session can still carry a previous jump's unfired scroll. This open is
            // not that jump — the root requests a scroll after `openPane` returns — so an ordinary
            // reopen from the toolbar or the list must not inherit it and jump somewhere the user
            // did not ask for. Which staged comments render is not session state, so it needs no
            // equivalent reset.
            paneSessions[target]?.pendingCommentScrollTarget = nil
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
        // The session is going, so a debounced refetch waiting on it has nothing left to refresh.
        remoteRefreshTasks.removeValue(forKey: target)?.cancel()
        paneSessions[target] = nil
        if activePaneTarget == target {
            activePaneTarget = nil
        }
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

    /// Synchronous session write addressed by target rather than by "whichever pane is active".
    /// Unlike `updateSession(_:generation:_:)` this takes no generation, because its callers run
    /// on the same cycle as the state they react to rather than after an `await`.
    func mutateSession(_ target: PullRequestPaneTarget, _ mutate: (inout PullRequestPaneSession) -> Void) {
        guard var session = paneSessions[target] else {
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

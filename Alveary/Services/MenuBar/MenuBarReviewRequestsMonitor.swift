import Foundation
import Observation

/// Keeps the status menu's "Needs review" list: the pull requests GitHub says are waiting on the
/// viewer's review, narrowed by the Pull requests screen's own filter (`PullRequestListFilter`),
/// minus those handed to an agent review (`MenuBarAgentReviewHandoffs`).
///
/// App-scoped because the status item outlives the window, and `PullRequestsViewModel` — the
/// window's list — does not; it reads the app-scoped service directly, as the host tool does.
/// Its reads are the screen's page one of `.reviewRequested` under the same status, which is what
/// lets one share a `gh` process with an identical in-flight window read through
/// `GitHubSharedReads`, and what lets every read it lands refresh the screen's caches too.
///
/// - **One loop while active:** read at once, then every `interval`. A read GitHub rate-limits
///   waits until its `retryAt` instead.
/// - **A failure keeps the last good rows.** Only a failure before any success reads `.failed`,
///   so a transient blip never empties the menu or drops the badge.
/// - **Only the status is searched.** A status change reads again; repositories and the ignore
///   list narrow at read time in `visibleSummaries`, and an observation on
///   `PullRequestIgnoreService` fires `onChange`, so ignoring the last waiting pull request in the
///   window clears the badge without a read.
/// - **Reads are shared both ways.** Every read this lands is written into `PullRequestsListCache`
///   and posted as a `PullRequestBucketRefresh`, so the screen paints it on its next launch and an
///   open window shows it now; a page-one reload the screen lands arrives the same way, and
///   `adopt(_:)` takes it so the menu follows without a read.
@MainActor
final class MenuBarReviewRequestsMonitor {
    typealias Sleeper = @Sendable (Duration) async throws -> Void

    enum Phase: Equatable {
        case inactive
        /// Active, before any read has finished.
        case loading
        /// At least one read succeeded; later failures keep its rows.
        case loaded
        /// Active, and every read so far has failed.
        case failed
    }

    /// The `GitHubRequestOrigin` label the usage ledger attributes these reads to.
    nonisolated static let requestOrigin = "menu-bar"

    private(set) var phase: Phase = .inactive
    /// Fired after every change a reader could see: a read landing, activation, deactivation, or
    /// the ignore list changing. The controller re-reads state from here rather than being handed it.
    var onChange: (@MainActor () -> Void)?

    var visibleSummaries: [PullRequestSummary] {
        let ignoredIDs = ignoreService.effectiveIgnoredIDs
        return summaries.filter { filter.admits($0, ignoredIDs: ignoredIDs) && !agentReviews.hides($0.id) }
    }

    private var summaries: [PullRequestSummary] = []
    /// When `summaries` was read, by this monitor or the screen; what `adopt(_:)` compares against
    /// so an older read never replaces a newer one.
    private var summariesFetchedAt = Date.distantPast
    private var filter = AppSettings().pullRequestListFilter
    /// `nil` while inactive. Compared on every `configure`, because `.appSettingsChanged` posts on
    /// every settings write — switching settings tabs included — and each must not cost a read.
    private var interval: Duration?
    private var pollTask: Task<Void, Never>?
    private var remoteChangeTask: Task<Void, Never>?
    private var releaseRefreshTask: Task<Void, Never>?
    private var remoteChangeObserver: NSObjectProtocol?
    private var bucketRefreshObserver: NSObjectProtocol?
    /// Bumped on every activation and deactivation, so an ignore-list observation armed by an
    /// earlier activation stops re-arming instead of doubling up beside the current one.
    private var ignoreObservationGeneration = 0

    private let service: any PullRequestsService
    private let ignoreService: PullRequestIgnoreService
    private let agentReviews: MenuBarAgentReviewHandoffs
    private let listCache: PullRequestsListCache?
    private let notificationCenter: NotificationCenter
    private let pollsGitHub: Bool
    private let remoteChangeDelay: Duration
    private let now: @MainActor () -> Date
    private let sleep: Sleeper

    /// - Parameter pollsGitHub: `false` runs the whole lifecycle without ever reaching the
    ///   service. App-hosted unit tests start the real status item, and a read there would spawn
    ///   `gh` against the developer's account.
    init(
        service: any PullRequestsService,
        ignoreService: PullRequestIgnoreService,
        agentReviews: MenuBarAgentReviewHandoffs? = nil,
        listCache: PullRequestsListCache? = nil,
        notificationCenter: NotificationCenter = .default,
        pollsGitHub: Bool = true,
        remoteChangeDelay: Duration = .seconds(2),
        now: @escaping @MainActor () -> Date = { Date() },
        sleep: @escaping Sleeper = { try await Task.sleep(for: $0) }
    ) {
        self.service = service
        self.ignoreService = ignoreService
        // Absent means nothing is ever handed off, which is the shape of a test that is not about it.
        self.agentReviews = agentReviews ?? MenuBarAgentReviewHandoffs(
            activity: nil,
            pendingProposalIdentifiers: { [] },
            notificationCenter: notificationCenter
        )
        self.listCache = listCache
        self.notificationCenter = notificationCenter
        self.pollsGitHub = pollsGitHub
        self.remoteChangeDelay = remoteChangeDelay
        self.now = now
        self.sleep = sleep
    }

    /// Starts, stops, or reschedules the loop. Does nothing when nothing changed.
    ///
    /// An interval or status change restarts with an immediate read rather than waiting out the
    /// interval, so a read already in flight is replaced instead of silently dropped; a narrowing
    /// that GitHub does not search only re-filters.
    func configure(isActive: Bool, interval: Duration, filter: PullRequestListFilter) {
        let requested = isActive ? interval : nil
        let previousFilter = self.filter
        self.filter = filter
        guard requested != self.interval else {
            guard requested != nil, filter != previousFilter else {
                return
            }
            if filter.status != previousFilter.status {
                restartPolling()
            }
            onChange?()
            return
        }
        let wasActive = self.interval != nil
        self.interval = requested
        guard requested != nil else {
            deactivate()
            return
        }
        if !wasActive {
            activate()
        }
        restartPolling()
    }

    /// Reads now and restarts the interval from here. Inert while inactive.
    func refreshNow() {
        guard interval != nil else {
            return
        }
        restartPolling()
    }

    /// Synchronous, because shutdown must not queue a `Task` hop (see `Alveary/App/AGENTS.md`).
    func stop() {
        interval = nil
        deactivate()
    }

    private func activate() {
        phase = .loading
        ignoreObservationGeneration += 1
        observeIgnoredPullRequests(generation: ignoreObservationGeneration)
        observeRemoteChanges()
        observeScreenRefreshes()
        observeAgentReviews()
        onChange?()
    }

    private func deactivate() {
        pollTask?.cancel()
        pollTask = nil
        remoteChangeTask?.cancel()
        remoteChangeTask = nil
        releaseRefreshTask?.cancel()
        releaseRefreshTask = nil
        if let remoteChangeObserver {
            notificationCenter.removeObserver(remoteChangeObserver)
        }
        remoteChangeObserver = nil
        if let bucketRefreshObserver {
            notificationCenter.removeObserver(bucketRefreshObserver)
        }
        bucketRefreshObserver = nil
        agentReviews.onChange = nil
        agentReviews.stop()
        ignoreObservationGeneration += 1
        let wasVisible = phase != .inactive
        phase = .inactive
        summaries = []
        summariesFetchedAt = .distantPast
        if wasVisible {
            onChange?()
        }
    }

    private func restartPolling() {
        pollTask?.cancel()
        let sleep = self.sleep
        pollTask = Task { [weak self] in
            var delay: Duration?
            while !Task.isCancelled {
                if let delay {
                    do {
                        try await sleep(delay)
                    } catch {
                        return
                    }
                }
                guard let self, let next = await self.poll() else {
                    return
                }
                delay = next
            }
        }
    }

    /// One read. Returns the wait before the next one, or `nil` once cancelled or deactivated.
    ///
    /// State is written only while the task is still live: shell teardown surfaces cancellation as
    /// a `PullRequestsServiceError`, and a replaced read must not overwrite its replacement's rows.
    private func poll() async -> Duration? {
        guard let interval else {
            return nil
        }
        guard pollsGitHub else {
            return interval
        }
        await ignoreService.loadIfNeeded()
        let status = filter.status
        let startedAt = now()
        let outcome: Result<PullRequestListResult, PullRequestsServiceError>
        do {
            let result = try await GitHubRequestOrigin.$current.withValue(Self.requestOrigin) {
                try await service.listInvolvedPullRequests(
                    buckets: [.reviewRequested],
                    status: status.status,
                    options: .firstPage
                )
            }
            outcome = .success(result)
        } catch let error as PullRequestsServiceError {
            outcome = .failure(error)
        } catch {
            outcome = .failure(.transport(error.localizedDescription))
        }
        guard !Task.isCancelled, let interval = self.interval else {
            return nil
        }
        agentReviews.readFinished(startedAt: startedAt)
        var next = interval
        switch outcome {
        case .success(let result):
            summaries = result.summariesByBucket[.reviewRequested] ?? []
            summariesFetchedAt = now()
            phase = .loaded
            share(result, status: status)
        case .failure(let error):
            if phase != .loaded {
                phase = .failed
            }
            if case .rateLimit(let limit) = error {
                next = max(interval, .seconds(limit.retryAt.timeIntervalSince(now())))
            }
        }
        onChange?()
        return next
    }

    /// Hands a landed read to the screen's caches: the file it paints from on launch, and — through
    /// the notification — the list an open window holds.
    private func share(_ result: PullRequestListResult, status: PullRequestStatusFilter) {
        let refresh = PullRequestBucketRefresh(
            bucket: .reviewRequested,
            status: status,
            summaries: summaries,
            pageInfo: result.pageInfoByBucket[.reviewRequested],
            fetchedAt: summariesFetchedAt
        )
        if let listCache {
            let summaries = refresh.summaries
            Task {
                await listCache.replaceBucket(.reviewRequested, with: summaries, filter: status)
            }
        }
        notificationCenter.post(
            name: .pullRequestBucketRefreshed,
            object: self,
            userInfo: [PullRequestBucketRefresh.userInfoKey: refresh]
        )
    }

    /// Synchronous (`queue: nil`), so the menu has the rows by the time the screen's `post`
    /// returns. Every poster is `@MainActor`, which is what `assumeIsolated` rests on.
    private func observeScreenRefreshes() {
        bucketRefreshObserver = notificationCenter.addObserver(
            forName: .pullRequestBucketRefreshed,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let refresh = notification.userInfo?[PullRequestBucketRefresh.userInfoKey]
                as? PullRequestBucketRefresh else {
                return
            }
            // An identity rather than the object, which cannot cross into the main-actor closure.
            let poster = (notification.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, poster != ObjectIdentifier(self) else {
                    return
                }
                self.adopt(refresh)
            }
        }
    }

    /// Takes a page-one read of the review bucket the screen landed — the reload a review submitted
    /// from the pane ends in, say, which posts no announcement — so the menu follows it now rather
    /// than at its next poll. Only under the status it searches, and only rows newer than its own.
    ///
    /// The poll keeps its schedule: a read it already has in flight replaces these rows when it
    /// lands, which is no older than what the screen just read.
    private func adopt(_ refresh: PullRequestBucketRefresh) {
        guard interval != nil,
              refresh.bucket == .reviewRequested,
              refresh.status == filter.status,
              refresh.fetchedAt > summariesFetchedAt else {
            return
        }
        summaries = refresh.summaries
        summariesFetchedAt = refresh.fetchedAt
        phase = .loaded
        onChange?()
    }

    /// A hand-off changes what is visible on its own; a release also schedules the settling read
    /// that may lift its hide, so a pull request GitHub still lists comes back without waiting for
    /// the next poll.
    private func observeAgentReviews() {
        agentReviews.onChange = { [weak self] released in
            guard let self else {
                return
            }
            if released {
                self.scheduleReleaseRefresh()
            }
            self.onChange?()
        }
        agentReviews.start()
    }

    /// Rescheduled by each release, so a burst — a team review's several workers ending — costs one
    /// read, timed from the latest.
    private func scheduleReleaseRefresh() {
        releaseRefreshTask?.cancel()
        let sleep = self.sleep
        let delay = Duration.seconds(agentReviews.releaseSettle)
        releaseRefreshTask = Task { [weak self] in
            do {
                try await sleep(delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else {
                return
            }
            self.releaseRefreshTask = nil
            self.refreshNow()
        }
    }

    private func observeIgnoredPullRequests(generation: Int) {
        withObservationTracking {
            _ = ignoreService.effectiveIgnoredIDs
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.ignoreObservationGeneration == generation else {
                    return
                }
                self.observeIgnoredPullRequests(generation: generation)
                self.onChange?()
            }
        }
    }

    /// A review confirmed on a transcript card, or an agent's state change, can take a pull
    /// request out of the review-requested bucket; GitHub composes that bucket, so only a read
    /// can follow. Debounced so one agent turn's run of mutations costs one read. A review
    /// submitted from the pane's own footer posts no announcement; its list reload reaches the menu
    /// through `adopt(_:)` instead.
    ///
    /// Every poster is `@MainActor`, which is what `assumeIsolated` rests on.
    private func observeRemoteChanges() {
        remoteChangeObserver = notificationCenter.addObserver(
            forName: .pullRequestChangedOnGitHub,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let announcement = notification.userInfo?[PullRequestChangeNotificationKey.announcement]
                as? PullRequestChangeAnnouncement
            guard announcement?.affectsListRow == true else {
                return
            }
            MainActor.assumeIsolated {
                self?.scheduleRemoteChangeRefresh()
            }
        }
    }

    private func scheduleRemoteChangeRefresh() {
        remoteChangeTask?.cancel()
        let sleep = self.sleep
        let delay = remoteChangeDelay
        remoteChangeTask = Task { [weak self] in
            do {
                try await sleep(delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else {
                return
            }
            self.remoteChangeTask = nil
            self.refreshNow()
        }
    }
}

import Foundation

/// One involvement bucket's last successful fetch. `fetchedAt` is per bucket rather than one
/// list-wide timestamp because buckets are fetched independently — a tab that reuses a bucket
/// another tab loaded must still be able to tell how old that bucket is.
struct PullRequestBucketState: Equatable {
    var summaries: [PullRequestSummary]
    var fetchedAt: Date
    /// Where "Load more" resumes this bucket, and whether it has anything left. Written from every
    /// *fresh* apply — a page-one load, a status change, a refresh — so nothing has to reset them:
    /// the load that replaces a bucket's rows replaces its position with them.
    var endCursor: String?
    var hasNextPage: Bool

    init(
        summaries: [PullRequestSummary],
        fetchedAt: Date,
        endCursor: String? = nil,
        hasNextPage: Bool = false
    ) {
        self.summaries = summaries
        self.fetchedAt = fetchedAt
        self.endCursor = endCursor
        self.hasNextPage = hasNextPage
    }
}

// MARK: - Loading

extension PullRequestsViewModel {
    /// Warms the tab the screen will open on while the user is still elsewhere, so the first
    /// visit of a session usually issues nothing at all.
    ///
    /// Delegates to `refreshForScreen()` rather than introducing a second loading path: its
    /// halves are all idempotent — `hasLoadedListCache`, `inFlightBuckets`, and the per-bucket
    /// freshness cutoff — so the screen's own appearance load is a no-op inside the window.
    ///
    /// Gated on the setting that hides the sidebar row, since with the integration off there is
    /// no screen to warm. No settings service at all means no persisted tab either, which is the
    /// tests-and-previews shape rather than the app root, so it does not prefetch.
    func prefetchAtLaunch() async {
        guard settingsService?.current.pullRequestsEnabled == true else {
            return
        }
        await refreshForScreen()
    }

    /// Screen-appearance load: paints the persisted buckets once, then fetches whatever the
    /// visible tab still needs.
    func refreshForScreen() async {
        await loadCachedListIfNeeded()
        await loadIfNeeded(for: selectedFilter)
    }

    /// Fetches the buckets `tab` renders that are neither already in flight nor recently fetched.
    /// A tab whose buckets are all warm issues no request at all, which is what makes switching
    /// back to a visited tab instant.
    func loadIfNeeded(for tab: PullRequestsFilter) async {
        await load(buckets: staleBuckets(for: tab))
    }

    /// Spawns an unthrottled reload of the visible tab; for the header's explicit refresh action
    /// and for the epilogues that follow a mutation.
    func requestRefresh() {
        Task {
            await refresh()
        }
    }

    /// Reloads the visible tab's buckets, ignoring the freshness throttle.
    func refresh() async {
        await load(buckets: selectedFilter.requiredBuckets.subtracting(inFlightBuckets))
    }

    /// Clears the banner as well as the typed failures: the error banner offers this as its own
    /// action, so leaving the message up would read as the retry having failed instantly. The
    /// reload republishes it if the cause has not gone away.
    func retry() {
        bucketFailures = [:]
        errorMessage = nil
        requestRefresh()
    }

    /// Ages every loaded bucket out of the freshness window while keeping its rows on screen, so
    /// the visible tab refetches on its next load and the others refetch when next shown. For the
    /// events that invalidate all buckets at once: a status-filter change, or Alveary itself
    /// mutating a pull request somewhere else.
    ///
    /// The paging position goes with the staleness. A cursor is opaque and belongs to the search
    /// that produced it, so a status change would otherwise leave "Load more" offering to page the
    /// previous search's position under the new one; each bucket's next fresh apply restores it.
    func markAllBucketsStale() {
        for bucket in bucketStates.keys {
            bucketStates[bucket]?.fetchedAt = .distantPast
            bucketStates[bucket]?.endCursor = nil
            bucketStates[bucket]?.hasNextPage = false
        }
    }

    /// A tab's phase, derived from its buckets: anything loaded renders, so a bucket that failed
    /// beside a healthy one shows an error banner over rows rather than blanking the tab.
    func loadPhase(for tab: PullRequestsFilter) -> PullRequestsLoadPhase {
        let buckets = tab.requiredBuckets
        if hasLoadedData(for: tab) {
            return .loaded
        }
        if buckets.contains(where: inFlightBuckets.contains) {
            return .loading
        }
        if let error = orderedFailures(in: buckets).first {
            return .unavailable(PullRequestsUnavailableReason(error))
        }
        return .idle
    }

    func hasLoadedData(for tab: PullRequestsFilter) -> Bool {
        tab.requiredBuckets.contains { bucketStates[$0] != nil }
    }

    /// Whether the tab's footer offers another page. A bucket already in flight is excluded so the
    /// button cannot queue a second page on top of a load that is about to replace its cursor.
    func canLoadMore(for tab: PullRequestsFilter) -> Bool {
        tab.requiredBuckets.contains { bucket in
            !inFlightBuckets.contains(bucket) && bucketStates[bucket]?.hasNextPage == true
        }
    }

    func requestLoadMore() {
        Task {
            await loadMore()
        }
    }

    /// Appends the next page of every bucket the visible tab still has one for.
    ///
    /// The rows land on one barrier, like `load(buckets:)`, and are *appended* rather than
    /// replacing what is held; `fetchedAt` is deliberately untouched, so paging deeper never
    /// refreshes the freshness throttle that governs page one.
    func loadMore() async {
        let tab = selectedFilter
        let pending = tab.requiredBuckets.filter { bucket in
            !inFlightBuckets.contains(bucket) && bucketStates[bucket]?.hasNextPage == true
        }
        guard !pending.isEmpty, !isLoadingMore else {
            return
        }
        var cursors: [PullRequestInvolvementBucket: String] = [:]
        for bucket in pending {
            cursors[bucket] = bucketStates[bucket]?.endCursor
        }
        isLoadingMore = true
        inFlightBuckets.formUnion(pending)
        let filter = selectedStatusFilter
        let outcomes = await fetchConcurrently(buckets: pending, status: filter.status, cursors: cursors)
        inFlightBuckets.subtract(pending)
        isLoadingMore = false

        guard !Task.isCancelled else {
            // Same rule as `load(buckets:)`: applying part of a cancelled fan-out would leave the
            // tab holding rows from a page whose siblings never arrived.
            return
        }
        guard selectedStatusFilter == filter else {
            // These rows answer the previous search. The buckets were skipped as in-flight while
            // this ran, so hand off rather than dropping them silently.
            await loadIfNeeded(for: selectedFilter)
            return
        }
        applyMore(outcomes)
    }

    // MARK: - Private

    private func staleBuckets(for tab: PullRequestsFilter) -> Set<PullRequestInvolvementBucket> {
        let cutoff = now().addingTimeInterval(-PullRequestsViewModel.refreshInterval)
        return tab.requiredBuckets.filter { bucket in
            guard !inFlightBuckets.contains(bucket) else {
                return false
            }
            guard let state = bucketStates[bucket] else {
                return true
            }
            return state.fetchedAt <= cutoff
        }
    }

    /// Fetches every bucket named concurrently, then applies them in one pass, so a tab settles in
    /// a single UI invalidation no matter how many involvements it renders.
    private func load(buckets: Set<PullRequestInvolvementBucket>) async {
        guard !buckets.isEmpty else {
            return
        }
        inFlightBuckets.formUnion(buckets)
        let filter = selectedStatusFilter
        let outcomes = await fetchConcurrently(buckets: buckets, status: filter.status, cursors: [:])
        inFlightBuckets.subtract(buckets)

        guard !Task.isCancelled else {
            // Leaving the screen cancels the load. Legs that already succeeded are dropped rather
            // than applied: a partial apply would stamp a half-loaded tab with a fresh `fetchedAt`,
            // and the freshness throttle would then suppress the load that should complete it.
            // Shell teardown also wraps cancellation in a `PullRequestsServiceError`, so the thrown
            // type cannot be trusted for this — only the cancellation flag can.
            return
        }
        guard selectedStatusFilter == filter else {
            // The status filter moved while this was in flight, so these rows answer the previous
            // search. Hand off rather than just dropping them: `selectStatusFilter` skipped these
            // buckets while they were in flight, so nothing else would reload them.
            await loadIfNeeded(for: selectedFilter)
            return
        }
        apply(outcomes)
    }

    /// One request per bucket, in parallel. GitHub runs a batched request's aliased searches
    /// serially, so a three-bucket tab used to cost about three searches where concurrently it
    /// costs about one. Collecting the legs here rather than applying each as it lands is what
    /// keeps the single settle — see `apply(_:)`.
    ///
    /// `cursors` is empty for a page-one load and carries one entry per bucket for "Load more"; a
    /// leg only ever receives its own bucket's position.
    private func fetchConcurrently(
        buckets: Set<PullRequestInvolvementBucket>,
        status: PullRequestStatus?,
        cursors: [PullRequestInvolvementBucket: String]
    ) async -> [PullRequestInvolvementBucket: PullRequestBucketOutcome] {
        await withTaskGroup(of: (PullRequestInvolvementBucket, PullRequestBucketOutcome).self) { group in
            for bucket in buckets {
                let options = PullRequestListOptions(
                    pageSize: PullRequestsViewModel.listPageSize,
                    cursors: cursors[bucket].map { [bucket: $0] } ?? [:]
                )
                group.addTask { [service] in
                    do {
                        let result = try await service.listInvolvedPullRequests(
                            buckets: [bucket],
                            status: status,
                            options: options
                        )
                        return (bucket, .success(result))
                    } catch let error as PullRequestsServiceError {
                        return (bucket, .failure(error))
                    } catch {
                        return (bucket, .failure(.transport(error.localizedDescription)))
                    }
                }
            }
            var outcomes: [PullRequestInvolvementBucket: PullRequestBucketOutcome] = [:]
            for await (bucket, outcome) in group {
                outcomes[bucket] = outcome
            }
            return outcomes
        }
    }

    /// The barrier every concurrent leg lands on. Applying per leg would publish once per bucket
    /// and write the cache once per bucket, which is the "reads as loading twice" flicker the
    /// batched request existed to avoid.
    private func apply(_ outcomes: [PullRequestInvolvementBucket: PullRequestBucketOutcome]) {
        // Split in `allCases` order rather than the dictionary's, so which leg finished first
        // cannot change what this pass does.
        var successes: [(bucket: PullRequestInvolvementBucket, result: PullRequestListResult)] = []
        var failures: [(bucket: PullRequestInvolvementBucket, error: PullRequestsServiceError)] = []
        for bucket in PullRequestInvolvementBucket.allCases {
            switch outcomes[bucket] {
            case .success(let result):
                successes.append((bucket, result))
            case .failure(let error):
                failures.append((bucket, error))
            case nil:
                continue
            }
        }

        if !successes.isEmpty {
            let fetchedAt = now()
            var collectedWarnings: [String] = []
            for (bucket, result) in successes {
                // Absent means the bucket came back empty — a SAML-forbidden bucket decodes as null
                // and must still count as fetched, or it would be reloaded on every pass.
                let pageInfo = result.pageInfoByBucket[bucket]
                bucketStates[bucket] = PullRequestBucketState(
                    summaries: result.summariesByBucket[bucket] ?? [],
                    fetchedAt: fetchedAt,
                    endCursor: pageInfo?.endCursor,
                    hasNextPage: pageInfo?.hasNextPage ?? false
                )
                bucketFailures[bucket] = nil
                // Every leg carries the same SAML message, so without this the banner repeats it
                // once per bucket.
                for warning in result.warnings where !collectedWarnings.contains(warning) {
                    collectedWarnings.append(warning)
                }
            }
            rebuildItems()
            warnings = collectedWarnings
            touchReferenceDate()
            saveListCache()
        }

        // After the successes, on both counts: a healthy sibling clears its own `bucketFailures`
        // entry, and `hasLoadedData` below has to see the rows this pass just landed.
        for (bucket, error) in failures {
            bucketFailures[bucket] = error
        }
        guard let failure = failures.first?.error else {
            errorMessage = nil
            return
        }
        // A tab still holding rows keeps them and says why the load failed; one with nothing to
        // show goes unavailable, which `loadPhase(for:)` derives from `bucketFailures`. A load that
        // failed entirely leaves `warnings` alone — they still describe the rows on screen.
        if hasLoadedData(for: selectedFilter) {
            errorMessage = failure.localizedDescription
        }
    }

    /// The load-more barrier. Unlike `apply(_:)` this *adds* to what each bucket holds and leaves
    /// `fetchedAt` alone, so a deeper page never satisfies the page-one freshness throttle — and a
    /// later refresh legitimately replaces the bucket, dropping the appended pages by design.
    ///
    /// A failed leg keeps its `hasNextPage`, so the footer stays and doubles as the retry, and it
    /// records no `bucketFailures` entry: the tab is rendering rows, so a deeper page failing must
    /// not be able to send it to `.unavailable`.
    private func applyMore(_ outcomes: [PullRequestInvolvementBucket: PullRequestBucketOutcome]) {
        var appended = false
        var failure: PullRequestsServiceError?
        // `allCases` order rather than the dictionary's, so which leg landed first cannot change
        // the error reported or the order rows are appended in.
        for bucket in PullRequestInvolvementBucket.allCases {
            switch outcomes[bucket] {
            case .success(let result):
                guard var state = bucketStates[bucket] else {
                    // The bucket was dropped while the page was in flight; appending would
                    // resurrect it without its first page.
                    continue
                }
                let held = Set(state.summaries.map(\.id))
                state.summaries += (result.summariesByBucket[bucket] ?? []).filter { !held.contains($0.id) }
                let pageInfo = result.pageInfoByBucket[bucket]
                state.endCursor = pageInfo?.endCursor
                state.hasNextPage = pageInfo?.hasNextPage ?? false
                bucketStates[bucket] = state
                appended = true
            case .failure(let error):
                failure = failure ?? error
            case nil:
                continue
            }
        }
        if appended {
            rebuildItems()
            saveListCache()
        }
        errorMessage = failure?.localizedDescription
    }

    /// Deterministic pick when several of a tab's buckets failed differently.
    private func orderedFailures(
        in buckets: Set<PullRequestInvolvementBucket>
    ) -> [PullRequestsServiceError] {
        PullRequestInvolvementBucket.allCases
            .filter(buckets.contains)
            .compactMap { bucketFailures[$0] }
    }

    /// Paints the persisted buckets once per app run, so the screen shows the previous rows
    /// instantly while the network load runs behind it.
    private func loadCachedListIfNeeded() async {
        guard !hasLoadedListCache else {
            return
        }
        hasLoadedListCache = true
        guard bucketStates.isEmpty,
              let listCache,
              let cached = await listCache.load(filter: selectedStatusFilter) else {
            return
        }
        // A load may have landed while the cache read was in flight.
        guard bucketStates.isEmpty else {
            return
        }
        for (bucket, summaries) in cached {
            // Dated to the distant past so a painted bucket always reads as stale: the cache
            // exists to fill the first frame, never to satisfy the freshness throttle.
            bucketStates[bucket] = PullRequestBucketState(summaries: summaries, fetchedAt: .distantPast)
        }
        rebuildItems()
        touchReferenceDate()
    }

    /// Persists every bucket held, not just the ones a load refreshed, so a lazy per-tab fetch
    /// cannot drop another tab's cached rows.
    ///
    /// Only the first page is persisted: the cache stores no cursors, and painting it is followed
    /// by a page-one fetch that replaces the bucket anyway, so appended pages would be rows the
    /// next load discards.
    private func saveListCache() {
        guard let listCache else {
            return
        }
        let snapshot = bucketStates.mapValues { Array($0.summaries.prefix(PullRequestsViewModel.listPageSize)) }
        let filter = selectedStatusFilter
        Task.detached {
            await listCache.save(snapshot, filter: filter)
        }
    }
}

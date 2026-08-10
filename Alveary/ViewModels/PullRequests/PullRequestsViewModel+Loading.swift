import Foundation

/// One involvement bucket's last successful fetch. `fetchedAt` is per bucket rather than one
/// list-wide timestamp because buckets are fetched independently — a tab that reuses a bucket
/// another tab loaded must still be able to tell how old that bucket is.
struct PullRequestBucketState: Equatable {
    var summaries: [PullRequestSummary]
    var fetchedAt: Date
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

    func retry() {
        bucketFailures = [:]
        requestRefresh()
    }

    /// Ages every loaded bucket out of the freshness window while keeping its rows on screen, so
    /// the visible tab refetches on its next load and the others refetch when next shown. For the
    /// events that invalidate all buckets at once: a status-filter change, or Alveary itself
    /// mutating a pull request somewhere else.
    func markAllBucketsStale() {
        for bucket in bucketStates.keys {
            bucketStates[bucket]?.fetchedAt = .distantPast
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
        let outcomes = await fetchConcurrently(buckets: buckets, status: filter.status)
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
    private func fetchConcurrently(
        buckets: Set<PullRequestInvolvementBucket>,
        status: PullRequestStatus?
    ) async -> [PullRequestInvolvementBucket: PullRequestBucketOutcome] {
        await withTaskGroup(of: (PullRequestInvolvementBucket, PullRequestBucketOutcome).self) { group in
            for bucket in buckets {
                group.addTask { [service] in
                    do {
                        let result = try await service.listInvolvedPullRequests(
                            buckets: [bucket],
                            status: status
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
                bucketStates[bucket] = PullRequestBucketState(
                    summaries: result.summariesByBucket[bucket] ?? [],
                    fetchedAt: fetchedAt
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
            normalizeRepositoryFilter()
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
        normalizeRepositoryFilter()
    }

    /// Persists every bucket held, not just the ones a load refreshed, so a lazy per-tab fetch
    /// cannot drop another tab's cached rows.
    private func saveListCache() {
        guard let listCache else {
            return
        }
        let snapshot = bucketStates.mapValues(\.summaries)
        let filter = selectedStatusFilter
        Task.detached {
            await listCache.save(snapshot, filter: filter)
        }
    }
}

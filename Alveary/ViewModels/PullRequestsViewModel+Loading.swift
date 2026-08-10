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

    /// One batched request for every bucket named, so a tab always settles in a single UI
    /// invalidation no matter how many involvements it renders.
    private func load(buckets: Set<PullRequestInvolvementBucket>) async {
        guard !buckets.isEmpty else {
            return
        }
        inFlightBuckets.formUnion(buckets)
        let filter = selectedStatusFilter
        let outcome: Result<PullRequestListResult, any Error>
        do {
            outcome = .success(try await service.listInvolvedPullRequests(buckets: buckets, status: filter.status))
        } catch {
            outcome = .failure(error)
        }
        inFlightBuckets.subtract(buckets)

        guard selectedStatusFilter == filter else {
            // The status filter moved while this was in flight, so these rows answer the previous
            // search. Hand off rather than just dropping them: `selectStatusFilter` skipped these
            // buckets while they were in flight, so nothing else would reload them.
            await loadIfNeeded(for: selectedFilter)
            return
        }
        switch outcome {
        case .success(let result):
            apply(result, for: buckets)
        case .failure(let error):
            applyFailure(error, for: buckets)
        }
    }

    private func apply(_ result: PullRequestListResult, for buckets: Set<PullRequestInvolvementBucket>) {
        let fetchedAt = now()
        for bucket in buckets {
            // Absent means the bucket came back empty — a SAML-forbidden bucket decodes as null
            // and must still count as fetched, or it would be reloaded on every pass.
            bucketStates[bucket] = PullRequestBucketState(
                summaries: result.summariesByBucket[bucket] ?? [],
                fetchedAt: fetchedAt
            )
            bucketFailures[bucket] = nil
        }
        rebuildItems()
        warnings = result.warnings
        errorMessage = nil
        touchReferenceDate()
        normalizeRepositoryFilter()
        saveListCache()
    }

    private func applyFailure(_ error: any Error, for buckets: Set<PullRequestInvolvementBucket>) {
        if error is CancellationError {
            // Leaving the screen cancels the load; that is not an error worth a banner.
            return
        }
        guard !Task.isCancelled else {
            // Shell teardown wraps cancellation in service errors; same non-error.
            return
        }
        let serviceError = error as? PullRequestsServiceError ?? .transport(error.localizedDescription)
        for bucket in buckets {
            bucketFailures[bucket] = serviceError
        }
        // A tab still holding rows keeps them and says why the refresh failed; one with nothing to
        // show goes unavailable, which `loadPhase(for:)` derives from `bucketFailures`.
        if hasLoadedData(for: selectedFilter) {
            errorMessage = serviceError.localizedDescription
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

import Foundation

// Taking a bucket another surface read — the status menu's background poll — into the list, so
// the screen shows it and its next cache save does not write the older rows back over it.
extension PullRequestsViewModel {
    /// Synchronous (`queue: nil`) like `observeRemoteChanges()`, so the rows are in the list by the
    /// time the poster's `post` returns. Every poster is `@MainActor`, which is what
    /// `assumeIsolated` rests on; keep it that way.
    func observeBackgroundRefreshes() {
        backgroundRefreshObserver = notificationCenter.addObserver(
            forName: .pullRequestBucketRefreshed,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let refresh = notification.userInfo?[PullRequestBucketRefresh.userInfoKey]
                as? PullRequestBucketRefresh else {
                return
            }
            MainActor.assumeIsolated {
                self?.applyBackgroundRefresh(refresh)
            }
        }
    }

    func endBackgroundRefreshObservation() {
        if let backgroundRefreshObserver {
            notificationCenter.removeObserver(backgroundRefreshObserver)
            self.backgroundRefreshObserver = nil
        }
    }

    /// Replaces the bucket the way a page-one refresh would, except where that would be wrong
    /// or lose something:
    ///
    /// - **Before the list cache has painted**, the poller has already written the file that
    ///   paint reads, and a bucket landing first would make the paint skip every other bucket.
    /// - **Under another status**, the rows answer a different search.
    /// - **While this bucket is in flight**, its own load lands shortly, and this would only be
    ///   overwritten by it.
    /// - **When the held bucket is newer**, or **paged past page one** — a background read
    ///   must not shrink a list the user scrolled deeper with Load more.
    func applyBackgroundRefresh(_ refresh: PullRequestBucketRefresh) {
        guard hasLoadedListCache,
              refresh.status == selectedStatusFilter,
              !inFlightBuckets.contains(refresh.bucket) else {
            return
        }
        if let held = bucketStates[refresh.bucket] {
            guard held.fetchedAt < refresh.fetchedAt,
                  held.summaries.count <= PullRequestsViewModel.listPageSize else {
                return
            }
        }
        bucketStates[refresh.bucket] = PullRequestBucketState(
            summaries: refresh.summaries,
            fetchedAt: refresh.fetchedAt,
            endCursor: refresh.pageInfo?.endCursor,
            hasNextPage: refresh.pageInfo?.hasNextPage ?? false
        )
        bucketFailures[refresh.bucket] = nil
        rebuildItems()
        touchReferenceDate()
        saveListCache()
    }
}

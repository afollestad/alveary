import Foundation

// Sharing page-one bucket reads with the status menu's background poll, in both directions: its
// reads come into the list, so the screen shows them and its next cache save does not write the
// older rows back over them, and this list's own loads go out, so the menu follows a reload here.
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
            // An identity rather than the object, which cannot cross into the main-actor closure.
            let poster = (notification.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, poster != ObjectIdentifier(self) else {
                    return
                }
                self.applyBackgroundRefresh(refresh)
            }
        }
    }

    /// Hands a page-one load of the review bucket to the status menu, so a reload here — the one a
    /// review submitted from the pane ends in, say — takes the pull request out of the menu now
    /// rather than at its next poll. Only the bucket the menu lists goes out.
    func announceBucketRefreshes(_ landed: [PullRequestInvolvementBucket: PullRequestListPageInfo?]) {
        let bucket = PullRequestInvolvementBucket.reviewRequested
        guard let pageInfo = landed[bucket], let state = bucketStates[bucket] else {
            return
        }
        let refresh = PullRequestBucketRefresh(
            bucket: bucket,
            status: selectedStatusFilter,
            summaries: state.summaries,
            pageInfo: pageInfo,
            fetchedAt: state.fetchedAt
        )
        notificationCenter.post(
            name: .pullRequestBucketRefreshed,
            object: self,
            userInfo: [PullRequestBucketRefresh.userInfoKey: refresh]
        )
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

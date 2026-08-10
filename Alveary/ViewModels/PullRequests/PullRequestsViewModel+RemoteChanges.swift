import Foundation

// Catching an open pane and the list up with a pull request Alveary changed somewhere else — an
// `alveary_host` mutation, or a review proposal confirmed on its transcript card.
//
// Nothing here is re-derived locally: `PullRequestDetail.reviewers`, its timeline, and the list's
// review-requested bucket are all composed by GitHub, so only a refetch can move them.
extension PullRequestsViewModel {
    /// Observes announcements synchronously (`queue: nil`), which is what makes the submitting
    /// check below deterministic: the block runs inside the poster's `post`, before the pane's own
    /// submit epilogue can clear the flag. An async stream would resume only at the poster's next
    /// suspension, so the check would pass or fail on how slow GitHub happened to be.
    ///
    /// Every poster is `@MainActor`, which is what `assumeIsolated` rests on; keep it that way.
    func observeRemoteChanges() {
        remoteChangeObserver = notificationCenter.addObserver(
            forName: .pullRequestChangedOnGitHub,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let announcement = notification.userInfo?[
                PullRequestChangeNotificationKey.announcement
            ] as? PullRequestChangeAnnouncement else {
                return
            }
            MainActor.assumeIsolated {
                self?.handleRemoteChange(announcement)
            }
        }
    }

    /// Torn down from `deinit`. The debounced refetches are unstructured, so nothing else would
    /// stop one that outlived the view model holding its session.
    func endRemoteChangeObservation() {
        if let remoteChangeObserver {
            notificationCenter.removeObserver(remoteChangeObserver)
            self.remoteChangeObserver = nil
        }
        remoteListRefreshTask?.cancel()
        for task in remoteRefreshTasks.values {
            task.cancel()
        }
    }

    func handleRemoteChange(_ announcement: PullRequestChangeAnnouncement) {
        let target = PullRequestPaneTarget.details(announcement.identifier)
        // A submit from this pane's own footer already owns the reload that follows it, and its
        // version additionally clears the draft it published — which this one must not do.
        if let session = paneSessions[target], !session.pendingReview.isSubmitting {
            scheduleRemoteDetailRefresh(target)
        }
        // Not gated on a pane: the list screen can be showing a row for a pull request the agent
        // just closed with nothing open beside it.
        if announcement.affectsListRow {
            scheduleRemoteListRefresh()
        }
    }

    /// Delays the refetch so one agent turn's worth of mutations costs one round trip. An
    /// address-feedback run answers and resolves several threads in a row, and each of those is
    /// its own announcement.
    private func scheduleRemoteDetailRefresh(_ target: PullRequestPaneTarget) {
        remoteRefreshTasks[target]?.cancel()
        remoteRefreshTasks[target] = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            try? await Task.sleep(for: remoteRefreshDelay)
            // A cancelled run clears nothing: its handle already belongs to the schedule that
            // replaced it, mirroring the proposal coordinator's preview tasks.
            guard !Task.isCancelled else {
                return
            }
            remoteRefreshTasks[target] = nil
            refreshDetailAfterRemoteChange(target: target)
        }
    }

    private func scheduleRemoteListRefresh() {
        remoteListRefreshTask?.cancel()
        remoteListRefreshTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            try? await Task.sleep(for: remoteRefreshDelay)
            guard !Task.isCancelled else {
                return
            }
            remoteListRefreshTask = nil
            // The mutation may have moved rows in buckets the visible tab does not render — an
            // agent closing an authored pull request while Reviewing is up — and `refresh()`
            // reloads only the visible tab's buckets. Staling the rest keeps a tab visited
            // inside the freshness window from painting the pre-mutation row as current.
            markAllBucketsStale()
            await refresh()
        }
    }
}

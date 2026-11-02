import Foundation

/// A page-one read of one involvement bucket, shared between the Pull requests screen and the
/// status menu's poll so whichever surface reads it, the other catches up without a read of its
/// own: the poll's reads reach the screen's list and the cache it saves, and the screen's reloads —
/// a review submitted from the pane among them — reach the menu.
///
/// A notification because the poller is app-scoped and the screen's view model is window-lived,
/// so neither can hold the other. Each side skips its own posts and rows older than its own;
/// `PullRequestsViewModel.applyBackgroundRefresh(_:)` and `MenuBarReviewRequestsMonitor`'s
/// `adopt(_:)` own when each takes one.
struct PullRequestBucketRefresh: Equatable, Sendable {
    static let userInfoKey = "bucketRefresh"

    let bucket: PullRequestInvolvementBucket
    /// The search the rows answer. A list showing another status must not take them.
    let status: PullRequestStatusFilter
    let summaries: [PullRequestSummary]
    let pageInfo: PullRequestListPageInfo?
    let fetchedAt: Date
}

extension Notification.Name {
    static let pullRequestBucketRefreshed = Notification.Name("pullRequestBucketRefreshed")
}

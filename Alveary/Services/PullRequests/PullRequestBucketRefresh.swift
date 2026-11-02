import Foundation

/// A page-one read of one involvement bucket made outside the Pull requests screen — the status
/// menu's background poll — handed to the screen so its list, and the cache it saves, catch up
/// without a read of their own.
///
/// A notification because the poller is app-scoped and the screen's view model is window-lived,
/// so neither can hold the other; `PullRequestsViewModel.applyBackgroundRefresh(_:)` owns when the
/// list takes it.
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

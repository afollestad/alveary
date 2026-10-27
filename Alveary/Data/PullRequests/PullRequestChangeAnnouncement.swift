import Foundation

/// Says that Alveary just changed a pull request on GitHub from somewhere other than its detail
/// pane — an `alveary_host` mutation, or a review proposal confirmed on its transcript card.
///
/// The host-tool service is app-scoped and the review-proposal coordinator is built before the
/// browsing view model, so neither can reach a pane session directly; the ask travels as a
/// notification the way `PullRequestPaneRequest` does.
struct PullRequestChangeAnnouncement: Equatable {
    let identifier: PullRequestIdentifier
    /// Set when the change can move the row between the list's involvement buckets or change its
    /// status glyph — a submitted review or a state change — so the list is refetched beside the
    /// pane. A comment or a resolved thread moves neither.
    let affectsListRow: Bool
}

/// An edit or deletion Alveary made to a published review comment, from a submitted card or the pane, so every
/// submitted card showing that comment follows without a fetch. Node ids are global, so no pull request rides along.
struct PullRequestReviewCommentChange: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case edited(String)
        case deleted
        /// A fresh read found the viewer may no longer edit or delete it.
        case permissionsChanged(canUpdate: Bool, canDelete: Bool)
    }

    let commentNodeID: String
    let kind: Kind
}

enum PullRequestChangeNotificationKey {
    static let announcement = "announcement"
    static let commentChange = "commentChange"
}

extension Notification.Name {
    static let pullRequestChangedOnGitHub = Notification.Name("pullRequestChangedOnGitHub")
    static let pullRequestReviewCommentChanged = Notification.Name("pullRequestReviewCommentChanged")
}

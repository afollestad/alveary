import Foundation

/// A linked pull request together with the owner whose column stores it.
///
/// The toolbar and popover render these instead of bare `LinkedPullRequest`
/// values because a project selection aggregates its own links with its child
/// threads' — so a rendered row must remember which owner mutations (unlink,
/// status write-back, snapshot refresh) are addressed to.
struct OwnedPullRequestLink: Equatable, Identifiable {
    let link: LinkedPullRequest
    let owner: PullRequestLinkOwner
    /// Non-nil when the link is surfaced on a project but stored on one of its
    /// child threads; names that thread for the popover row.
    let sourceLabel: String?

    init(link: LinkedPullRequest, owner: PullRequestLinkOwner, sourceLabel: String? = nil) {
        self.link = link
        self.owner = owner
        self.sourceLabel = sourceLabel
    }

    var id: PullRequestIdentifier { link.id }
}

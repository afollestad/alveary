import Foundation

extension Project {
    /// Linked pull requests in the order they were linked. Storage semantics
    /// (failure tolerance, empty-clears-to-nil) live in `LinkedPullRequestStorage`.
    var linkedPullRequests: [LinkedPullRequest] {
        get { LinkedPullRequestStorage.decode(linkedPullRequestsJSON) }
        set { linkedPullRequestsJSON = LinkedPullRequestStorage.encode(newValue) }
    }

    func isPullRequestLinked(_ identifier: PullRequestIdentifier) -> Bool {
        linkedPullRequests.contains { $0.id == identifier }
    }

    /// The project's own links followed by links stored on its live child
    /// threads, deduped by pull request with the project's own copy winning.
    ///
    /// Child links sort by `linkedAt` across threads so the section reads as one
    /// linking history; drafts and archived threads are excluded to match the
    /// sidebar's visible world. The `linkedPullRequestsJSON` pre-check keeps the
    /// per-render cost at plain property reads — only threads that actually hold
    /// links pay a JSON decode.
    var aggregatedPullRequestLinks: [OwnedPullRequestLink] {
        let owner = PullRequestLinkOwner.project(persistentModelID)
        var rows = linkedPullRequests.map {
            OwnedPullRequestLink(link: $0, owner: owner)
        }
        var seen = Set(rows.map(\.id))
        let childRows = threads
            .filter { !$0.isDraft && $0.archivedAt == nil && $0.linkedPullRequestsJSON != nil }
            .flatMap { thread in
                thread.linkedPullRequests.map { link in
                    OwnedPullRequestLink(
                        link: link,
                        owner: .thread(thread.persistentModelID),
                        sourceLabel: thread.displayName()
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.link.linkedAt != rhs.link.linkedAt {
                    return lhs.link.linkedAt < rhs.link.linkedAt
                }
                return lhs.id.displayKey < rhs.id.displayKey
            }
        for row in childRows where seen.insert(row.id).inserted {
            rows.append(row)
        }
        return rows
    }
}

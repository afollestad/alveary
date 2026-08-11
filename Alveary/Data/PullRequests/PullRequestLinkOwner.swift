import Foundation
import SwiftData

/// The sidebar selection a pull-request link belongs to: a thread or a project.
/// Carries persistent identifiers, not model references, so it is safe to hold
/// across an `await` and re-resolve through the fetch-backed helpers.
enum PullRequestLinkOwner: Hashable {
    case thread(PersistentIdentifier)
    case project(PersistentIdentifier)
}

extension ModelContext {
    /// The owner's stored links, or nil when the owner no longer resolves.
    func linkedPullRequests(for owner: PullRequestLinkOwner) -> [LinkedPullRequest]? {
        switch owner {
        case .thread(let id):
            return resolveThread(id: id)?.linkedPullRequests
        case .project(let id):
            return resolveProject(id: id)?.linkedPullRequests
        }
    }

    /// Writes the owner's links back; false when the owner no longer resolves.
    /// Does not save — callers own the save so a batch of mutations stays atomic.
    @discardableResult
    func setLinkedPullRequests(_ links: [LinkedPullRequest], for owner: PullRequestLinkOwner) -> Bool {
        switch owner {
        case .thread(let id):
            guard let thread = resolveThread(id: id) else {
                return false
            }
            thread.linkedPullRequests = links
        case .project(let id):
            guard let project = resolveProject(id: id) else {
                return false
            }
            project.linkedPullRequests = links
        }
        return true
    }
}

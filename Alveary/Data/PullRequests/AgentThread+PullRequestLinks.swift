import Foundation

extension AgentThread {
    /// Linked pull requests in the order they were linked. Storage semantics
    /// (failure tolerance, empty-clears-to-nil) live in `LinkedPullRequestStorage`.
    var linkedPullRequests: [LinkedPullRequest] {
        get { LinkedPullRequestStorage.decode(linkedPullRequestsJSON) }
        set { linkedPullRequestsJSON = LinkedPullRequestStorage.encode(newValue) }
    }

    func isPullRequestLinked(_ identifier: PullRequestIdentifier) -> Bool {
        linkedPullRequests.contains { $0.id == identifier }
    }
}

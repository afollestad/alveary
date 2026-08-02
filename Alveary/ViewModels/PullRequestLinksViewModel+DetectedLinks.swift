import Foundation
import SwiftData

extension PullRequestLinksViewModel {
    /// Links a pull request that `ConversationViewModel+PullRequestDetection` found
    /// in a transcript message.
    ///
    /// Deliberately separate from `link(_:owner:)`: that one drives the popover and
    /// writes `isLinking` / `linkErrorMessage`, which would make an unrelated
    /// background link disable the popover's button or show an error there. Failures
    /// throw so the app root can surface them where the user is actually looking.
    func linkDetectedPullRequest(_ identifier: PullRequestIdentifier, threadID: PersistentIdentifier) async throws {
        guard !linkingDetectedIdentifiers.contains(identifier) else {
            return
        }
        let owner = PullRequestLinkOwner.thread(threadID)
        guard let links = modelContext.linkedPullRequests(for: owner),
              !links.contains(where: { $0.id == identifier }) else {
            clearPendingPullRequestPrompts(for: identifier, threadID: threadID)
            return
        }

        linkingDetectedIdentifiers.insert(identifier)
        defer { linkingDetectedIdentifiers.remove(identifier) }

        let detail = try await service.fetchDetail(identifier)

        // Re-resolve after the await: the thread may be gone, or a concurrent link
        // for the same pull request may have landed meanwhile.
        guard let thread = modelContext.resolveThread(id: threadID) else {
            return
        }
        if !thread.isPullRequestLinked(identifier) {
            let linkedAt = now()
            thread.linkedPullRequests += [
                LinkedPullRequest(summary: Self.makeSummary(from: detail, linkedAt: linkedAt), linkedAt: linkedAt)
            ]
        }
        // Same save as the link, so an answered prompt cannot come back.
        thread.pendingPullRequestLinkPrompts = thread.pendingPullRequestLinkPrompts
            .filter { $0.identifier != identifier }
        try modelContext.save()
    }

    private func clearPendingPullRequestPrompts(for identifier: PullRequestIdentifier, threadID: PersistentIdentifier) {
        guard let thread = modelContext.resolveThread(id: threadID) else {
            return
        }
        let retained = thread.pendingPullRequestLinkPrompts.filter { $0.identifier != identifier }
        guard retained.count != thread.pendingPullRequestLinkPrompts.count else {
            return
        }
        thread.pendingPullRequestLinkPrompts = retained
        try? modelContext.save()
    }
}

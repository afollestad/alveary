import Foundation

// Timeline item mapping: GitHub's bare conversation rows (state changes, pushed
// commits, force pushes, review-request changes) become `PullRequestTimelineEvent`s.
extension GitHubPullRequestsService {
    private static let timelineEventKinds: [String: PullRequestTimelineEvent.Kind] = [
        "ReadyForReviewEvent": .readyForReview,
        "ConvertToDraftEvent": .convertToDraft,
        "ClosedEvent": .closed,
        "ReopenedEvent": .reopened,
        "MergedEvent": .merged,
        "HeadRefForcePushedEvent": .forcePushed,
        "ReviewRequestedEvent": .reviewRequested,
        "ReviewRequestRemovedEvent": .reviewRequestRemoved
    ]

    /// Unrequested or unrecognized timeline item types drop out.
    static func makeTimelineEvents(from node: GraphQLTimelineItemsNode?) -> [PullRequestTimelineEvent] {
        (node?.nodes ?? []).compactMap { item -> PullRequestTimelineEvent? in
            guard let item else {
                return nil
            }
            if item.typeName == "PullRequestCommit" {
                return makeCommitEvent(from: item.commit)
            }
            guard let kind = item.typeName.flatMap({ timelineEventKinds[$0] }) else {
                return nil
            }
            return PullRequestTimelineEvent(
                kind: kind,
                actorLogin: item.actor?.login ?? "ghost",
                actorAvatarURL: item.actor?.avatarUrl.flatMap(URL.init(string:)),
                createdAt: item.createdAt,
                detail: item.requestedReviewer.flatMap { $0.login ?? $0.name }
            )
        }
    }

    /// Commit rows attribute the commit author; unattributed commits fall back
    /// to the git author name.
    private static func makeCommitEvent(from commit: GraphQLTimelineCommitNode?) -> PullRequestTimelineEvent? {
        guard let commit else {
            return nil
        }
        let detail = [commit.abbreviatedOid, commit.messageHeadline]
            .compactMap { $0 }
            .joined(separator: " ")
        return PullRequestTimelineEvent(
            kind: .commit,
            actorLogin: commit.author?.user?.login ?? commit.author?.name ?? "ghost",
            actorAvatarURL: commit.author?.user?.avatarUrl.flatMap(URL.init(string:)),
            createdAt: commit.committedDate,
            detail: detail.isEmpty ? nil : detail
        )
    }
}

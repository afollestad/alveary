#if DEBUG
import Foundation

// What each fake pull request has said and done: the description, checks, reviewers, issue
// comments, reviews, review threads, and bare timeline events the Overview merges into one
// chronological conversation. The conversations themselves are split the way the list screen
// splits its tabs — `+AuthoredConversations.swift` and `+ReviewConversations.swift`.
//
// Two rules those fixtures obey, both of which fail silently:
//   - Every date is distinct. `PullRequestActivityEntry.entries(from:)` sorts on date and
//     `Array.sorted` is not stable, so two rows sharing a timestamp would swap between renders.
//   - Every thread anchor names a line the served diff actually draws, so the Changes tab places
//     it. See `DemoPullRequestFixtures+Diffs.swift`.
extension DemoPullRequestFixtures {
    static func detail(for id: PullRequestIdentifier) -> PullRequestDetail? {
        guard let summary = summary(for: id), let conversation = conversations[id] else {
            return nil
        }
        return makeDetail(summary: summary, conversation: conversation)
    }

    static let conversations: [PullRequestIdentifier: DemoPullRequestConversation] = [
        onboardingWalkthrough: onboardingConversation,
        searchEmptyState: emptyStateConversation,
        rateLimitMiddleware: rateLimiterConversation,
        webhookRetries: webhookRetriesConversation,
        tileCaching: tileCachingConversation,
        filterBottomSheet: filterSheetConversation
    ]

    /// Folds a conversation onto the fields the summary already carries. `viewerCanUpdate` follows
    /// authorship because the fixtures have one viewer; on GitHub it is a permission.
    private static func makeDetail(
        summary: PullRequestSummary,
        conversation: DemoPullRequestConversation
    ) -> PullRequestDetail {
        var detail = PullRequestDetail(
            id: summary.id,
            title: summary.title,
            url: summary.url,
            status: summary.status,
            authorLogin: summary.authorLogin,
            authorAvatarURL: nil,
            headRefName: summary.headRefName,
            baseRefName: summary.baseRefName,
            createdAt: conversation.createdAt,
            updatedAt: summary.updatedAt,
            additions: summary.additions,
            deletions: summary.deletions,
            changedFiles: conversation.changedFiles,
            bodyMarkdown: conversation.bodyMarkdown,
            reviewDecision: nil,
            checks: conversation.checks,
            comments: conversation.comments,
            reviews: conversation.reviews,
            reviewThreads: conversation.reviewThreads
        )
        detail.timelineEvents = conversation.timelineEvents
        detail.reviewers = conversation.reviewers
        detail.nodeID = "demo-pr-\(summary.id.repo)-\(summary.id.number)"
        detail.reactions = conversation.reactions
        detail.viewerLogin = viewerLogin
        detail.viewerCanUpdate = summary.isAuthored
        detail.pendingReviewNodeID = conversation.pendingReviewNodeID
        return detail
    }
}

/// Everything a fake pull request's detail varies. The rest — title, branches, status, diff stats —
/// comes from its `PullRequestSummary`, so the list screen and the pane cannot disagree.
struct DemoPullRequestConversation {
    let bodyMarkdown: String
    let createdAt: Date
    let changedFiles: Int
    var checks: [PullRequestCheck] = []
    var reviewers: [PullRequestReviewer] = []
    var comments: [PullRequestComment] = []
    var reviews: [PullRequestReview] = []
    var reviewThreads: [PullRequestReviewThread] = []
    var timelineEvents: [PullRequestTimelineEvent] = []
    var reactions: [PullRequestCommentReaction] = []
    /// Set only where the viewer holds an unsubmitted review; its threads are the `isPending` ones.
    var pendingReviewNodeID: String?
}
#endif

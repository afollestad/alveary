import Foundation

// Decodable node shapes for the GraphQL queries in
// `GitHubPullRequestsService+GraphQL.swift`.

// MARK: - Response envelopes

struct GraphQLResponse<DataShape: Decodable>: Decodable {
    let data: DataShape?
    let errors: [GraphQLErrorEntry]?
}

struct GraphQLErrorEntry: Decodable {
    let type: String?
    let message: String?
}

// MARK: - List response

struct ListGraphQLData: Decodable {
    let authored: SearchBucketNode?
    let requested: SearchBucketNode?
    let reviewed: SearchBucketNode?
}

struct SearchBucketNode: Decodable {
    // Edges are optional twice over: SAML-forbidden entries decode as `null`, and
    // `search(type: ISSUE)` can emit non-PR nodes as empty objects.
    let edges: [SearchEdgeNode?]?
    let pageInfo: SearchPageInfoNode?
}

/// One search hit plus the cursor that resumes *after* it. GitHub declares `cursor` non-null, so
/// an absent one means a malformed response rather than a real position; it decodes as optional
/// only so the row itself still maps.
struct SearchEdgeNode: Decodable {
    let cursor: String?
    let node: PullRequestListNode?
}

struct SearchPageInfoNode: Decodable {
    let endCursor: String?
    let hasNextPage: Bool?
}

struct PullRequestListNode: Decodable {
    let number: Int?
    let title: String?
    let url: String?
    let state: String?
    let isDraft: Bool?
    let author: GraphQLActorNode?
    let headRefName: String?
    let baseRefName: String?
    let updatedAt: Date?
    let additions: Int?
    let deletions: Int?
    // No `reviewDecision`: the list fragment does not select it — see the comment there.
    let repository: GraphQLRepositoryNode?
}

struct GraphQLActorNode: Decodable {
    let typeName: String?
    let login: String?
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case typeName = "__typename"
        case login
        case avatarUrl
    }
}

struct GraphQLRepositoryNode: Decodable {
    let nameWithOwner: String?
}

struct GraphQLRefNode: Decodable {
    let name: String?
}

struct GraphQLCommitsNode: Decodable {
    let nodes: [GraphQLCommitWrapperNode?]?
}

struct GraphQLCommitWrapperNode: Decodable {
    let commit: GraphQLCommitNode?
}

struct GraphQLCommitNode: Decodable {
    let statusCheckRollup: GraphQLRollupNode?
}

struct GraphQLRollupNode: Decodable {
    let state: String?
    let contexts: GraphQLRollupContextsNode?
}

struct GraphQLRollupContextsNode: Decodable {
    let nodes: [GraphQLCheckContextNode?]?
}

/// Union of `CheckRun` and `StatusContext` fields; every property is optional so one
/// struct decodes both concrete types.
struct GraphQLCheckContextNode: Decodable {
    let name: String?
    let status: String?
    let conclusion: String?
    let detailsUrl: String?
    let context: String?
    let state: String?
    let targetUrl: String?
}

// MARK: - Detail response

struct DetailGraphQLData: Decodable {
    let repository: DetailRepositoryNode?
    /// The signed-in user; attributes local pending comments before submission.
    let viewer: GraphQLActorNode?
}

struct DetailRepositoryNode: Decodable {
    let pullRequest: PullRequestDetailNode?
}

struct PullRequestDetailNode: Decodable {
    let id: String?
    let reactionGroups: [GraphQLReactionGroupNode?]?
    let number: Int?
    let title: String?
    let url: String?
    let state: String?
    let isDraft: Bool?
    let body: String?
    /// Whether the signed-in user may edit the pull request's own body.
    let viewerCanUpdate: Bool?
    let createdAt: Date?
    let updatedAt: Date?
    let author: GraphQLActorNode?
    let headRefName: String?
    let baseRefName: String?
    /// Null once the head branch is deleted, while `headRefName` keeps the name.
    let headRef: GraphQLRefNode?
    let additions: Int?
    let deletions: Int?
    let changedFiles: Int?
    let reviewDecision: String?
    let commits: GraphQLCommitsNode?
    let comments: GraphQLCommentsNode?
    let reviews: GraphQLReviewsNode?
    /// Aliased `reviews(states: [PENDING])`. GitHub only ever exposes the
    /// viewer's own pending review, so a hit here is always the viewer's draft.
    let pendingReview: GraphQLReviewsNode?
    let reviewThreads: GraphQLReviewThreadsNode?
    let reviewRequests: GraphQLReviewRequestsNode?
    let timelineItems: GraphQLTimelineItemsNode?
}

struct GraphQLCommentsNode: Decodable {
    /// Requested only by the review-thread selection, so a page smaller than the thread can
    /// still report the real total. Absent elsewhere.
    let totalCount: Int?
    let nodes: [GraphQLCommentNode?]?
}

struct GraphQLCommentNode: Decodable {
    let author: GraphQLActorNode?
    let body: String?
    let createdAt: Date?
    // Present only on review-thread comments, where edits and reactions are supported.
    let id: String?
    let databaseId: Int?
    let viewerCanUpdate: Bool?
    let viewerCanDelete: Bool?
    let diffHunk: String?
    /// `PENDING` / `SUBMITTED` on review-thread comments; absent on top-level
    /// conversation comments, which are never pending.
    let state: String?
    /// The review this thread comment was submitted with; nests the thread under
    /// its review card in the Overview timeline.
    let pullRequestReview: GraphQLNodeReference?
    let reactionGroups: [GraphQLReactionGroupNode?]?
}

/// A bare `{ id }` node reference.
struct GraphQLNodeReference: Decodable {
    let id: String?
}

struct GraphQLReactionGroupNode: Decodable {
    struct Reactors: Decodable {
        let totalCount: Int?
    }

    let content: String?
    let viewerHasReacted: Bool?
    let reactors: Reactors?
}

struct GraphQLReviewsNode: Decodable {
    let nodes: [GraphQLReviewNode?]?
}

struct GraphQLReviewNode: Decodable {
    let id: String?
    let databaseId: Int?
    let viewerCanUpdate: Bool?
    let author: GraphQLActorNode?
    let state: String?
    let body: String?
    let submittedAt: Date?
    let reactionGroups: [GraphQLReactionGroupNode?]?
}

struct GraphQLReviewThreadsNode: Decodable {
    let nodes: [GraphQLReviewThreadNode?]?
}

struct GraphQLReviewThreadNode: Decodable {
    let id: String?
    let path: String?
    let line: Int?
    let diffSide: String?
    let isResolved: Bool?
    let isOutdated: Bool?
    let comments: GraphQLCommentsNode?
}

struct GraphQLReviewRequestsNode: Decodable {
    let nodes: [GraphQLReviewRequestNode?]?
}

struct GraphQLReviewRequestNode: Decodable {
    let requestedReviewer: GraphQLRequestedReviewerNode?
}

/// Union of User/Bot (`login`) and Team (`name`) requested reviewers.
struct GraphQLRequestedReviewerNode: Decodable {
    let typeName: String?
    let login: String?
    let avatarUrl: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case typeName = "__typename"
        case login
        case avatarUrl
        case name
    }
}

struct GraphQLTimelineItemsNode: Decodable {
    let nodes: [GraphQLTimelineItemNode?]?
}

/// Shared shape for the requested timeline event types; `__typename` picks the kind.
struct GraphQLTimelineItemNode: Decodable {
    let typeName: String?
    let actor: GraphQLActorNode?
    let createdAt: Date?
    /// Review-request events only.
    let requestedReviewer: GraphQLRequestedReviewerNode?
    /// `PullRequestCommit` items only.
    let commit: GraphQLTimelineCommitNode?

    enum CodingKeys: String, CodingKey {
        case typeName = "__typename"
        case actor
        case createdAt
        case requestedReviewer
        case commit
    }
}

struct GraphQLTimelineCommitNode: Decodable {
    let abbreviatedOid: String?
    let messageHeadline: String?
    let committedDate: Date?
    let author: GraphQLCommitAuthorNode?
}

struct GraphQLCommitAuthorNode: Decodable {
    let name: String?
    let user: GraphQLActorNode?
}

// MARK: - Pending review mutation payloads

/// `addPullRequestReview`'s payload; the created review is PENDING because the
/// mutation omits `event`.
struct CreatePendingReviewGraphQLData: Decodable {
    struct Payload: Decodable {
        let pullRequestReview: GraphQLNodeReference?
    }

    let addPullRequestReview: Payload?
}

/// `addPullRequestReviewThread`'s payload. The thread selection matches the
/// detail query's, so it maps through `makeReviewThreads`' element mapper.
struct AddPendingReviewCommentGraphQLData: Decodable {
    struct Payload: Decodable {
        let thread: GraphQLReviewThreadNode?
    }

    let addPullRequestReviewThread: Payload?
}

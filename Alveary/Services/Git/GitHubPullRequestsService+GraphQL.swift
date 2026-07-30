import Foundation

// MARK: - Queries

extension GitHubPullRequestsService {
    static let listArgs: [String] = [
        "api", "graphql",
        "-f", "query=\(listQuery)",
        "-f", "authored=\(PullRequestInvolvementBucket.authored.searchQuery)",
        "-f", "requested=\(PullRequestInvolvementBucket.reviewRequested.searchQuery)",
        "-f", "reviewed=\(PullRequestInvolvementBucket.reviewed.searchQuery)"
    ]

    /// `addReaction` / `removeReaction` GraphQL mutations; both take the comment's
    /// node id and one fixed `ReactionContent` value.
    static func reactionArgs(add: Bool, subjectID: String, content: PullRequestReactionContent) -> [String] {
        let mutation = add ? "addReaction" : "removeReaction"
        return [
            "api", "graphql",
            "-f", """
            query=mutation($subjectId: ID!, $content: ReactionContent!) {
              \(mutation)(input: { subjectId: $subjectId, content: $content }) { clientMutationId }
            }
            """,
            "-f", "subjectId=\(subjectID)",
            "-f", "content=\(content.rawValue)"
        ]
    }

    static func detailArgs(for id: PullRequestIdentifier) -> [String] {
        [
            "api", "graphql",
            "-f", "query=\(detailQuery)",
            "-f", "owner=\(id.owner)",
            "-f", "name=\(id.repo)",
            "-F", "number=\(id.number)"
        ]
    }

    // One batched request for all three involvement buckets so every tab settles in
    // a single UI invalidation. The fragment deliberately omits `statusCheckRollup`:
    // the list never shows check status, and rollup is the field that makes GitHub's
    // GraphQL endpoint slow and 502-prone — without it the combined query is cheap.
    private static let listQuery = """
    query($authored: String!, $requested: String!, $reviewed: String!) {
      authored: search(type: ISSUE, query: $authored, first: 50) { nodes { ...pr } }
      requested: search(type: ISSUE, query: $requested, first: 50) { nodes { ...pr } }
      reviewed: search(type: ISSUE, query: $reviewed, first: 50) { nodes { ...pr } }
    }
    fragment pr on PullRequest {
      number title url state isDraft
      author { login avatarUrl(size: 64) }
      headRefName baseRefName updatedAt additions deletions reviewDecision
      repository { nameWithOwner }
    }
    """

    /// Shared by the detail query and `addPullRequestReviewThread`'s payload, so
    /// a thread created optimistically decodes exactly like a fetched one. Adding
    /// a field to only one of the two would leave freshly added pending comments
    /// missing state the rest of the UI reads.
    private static let reviewThreadSelection = """
    id path line diffSide isResolved isOutdated
    comments(first: 20) {
      nodes {
        id databaseId viewerCanUpdate viewerCanDelete diffHunk state
        pullRequestReview { id }
        author { __typename login avatarUrl(size: 64) } body createdAt
        reactionGroups { content viewerHasReacted reactors { totalCount } }
      }
    }
    """

    private static let detailQuery = """
    query($owner: String!, $name: String!, $number: Int!) {
      viewer { login avatarUrl(size: 64) }
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          id number title url state isDraft body viewerCanUpdate createdAt updatedAt
          reactionGroups { content viewerHasReacted reactors { totalCount } }
          author { login avatarUrl(size: 64) }
          headRefName baseRefName additions deletions changedFiles reviewDecision
          headRef { name }
          commits(last: 1) {
            nodes {
              commit {
                statusCheckRollup {
                  state
                  contexts(first: 50) {
                    nodes {
                      __typename
                      ... on CheckRun { name status conclusion detailsUrl }
                      ... on StatusContext { context state targetUrl }
                    }
                  }
                }
              }
            }
          }
          comments(first: 50) {
            nodes {
              id databaseId viewerCanUpdate viewerCanDelete
              author { __typename login avatarUrl(size: 64) } body createdAt
              reactionGroups { content viewerHasReacted reactors { totalCount } }
            }
          }
          reviews(first: 50) {
            nodes {
              id databaseId viewerCanUpdate
              author { __typename login avatarUrl(size: 64) } state body submittedAt
              reactionGroups { content viewerHasReacted reactors { totalCount } }
            }
          }
          pendingReview: reviews(first: 1, states: [PENDING]) { nodes { id } }
          reviewThreads(first: 100) { nodes { \(reviewThreadSelection) } }
          reviewRequests(first: 20) {
            nodes {
              requestedReviewer {
                __typename
                ... on User { login avatarUrl(size: 64) }
                ... on Bot { login avatarUrl(size: 64) }
                ... on Team { name }
              }
            }
          }
          timelineItems(
            itemTypes: [
              READY_FOR_REVIEW_EVENT, CONVERT_TO_DRAFT_EVENT, CLOSED_EVENT, REOPENED_EVENT,
              MERGED_EVENT, PULL_REQUEST_COMMIT, HEAD_REF_FORCE_PUSHED_EVENT,
              REVIEW_REQUESTED_EVENT, REVIEW_REQUEST_REMOVED_EVENT
            ],
            first: 100
          ) {
            nodes {
              __typename
              ... on ReadyForReviewEvent { actor { login avatarUrl(size: 64) } createdAt }
              ... on ConvertToDraftEvent { actor { login avatarUrl(size: 64) } createdAt }
              ... on ClosedEvent { actor { login avatarUrl(size: 64) } createdAt }
              ... on ReopenedEvent { actor { login avatarUrl(size: 64) } createdAt }
              ... on MergedEvent { actor { login avatarUrl(size: 64) } createdAt }
              ... on HeadRefForcePushedEvent { actor { login avatarUrl(size: 64) } createdAt }
              ... on ReviewRequestedEvent {
                actor { login avatarUrl(size: 64) } createdAt
                requestedReviewer {
                  __typename
                  ... on User { login }
                  ... on Bot { login }
                  ... on Team { name }
                }
              }
              ... on ReviewRequestRemovedEvent {
                actor { login avatarUrl(size: 64) } createdAt
                requestedReviewer {
                  __typename
                  ... on User { login }
                  ... on Bot { login }
                  ... on Team { name }
                }
              }
              ... on PullRequestCommit {
                commit {
                  abbreviatedOid messageHeadline committedDate
                  author { name user { login avatarUrl(size: 64) } }
                }
              }
            }
          }
        }
      }
    }
    """

    /// `markPullRequestReadyForReview`; takes the pull request's own node id.
    /// There is no REST counterpart for leaving draft.
    static func readyForReviewArgs(nodeID: String) -> [String] {
        [
            "api", "graphql",
            "-f", """
            query=mutation($pullRequestId: ID!) {
              markPullRequestReadyForReview(input: { pullRequestId: $pullRequestId }) { clientMutationId }
            }
            """,
            "-f", "pullRequestId=\(nodeID)"
        ]
    }

    // MARK: - Pending review mutations

    /// `addPullRequestReview` **without** an `event`, which is what leaves the
    /// review PENDING — the same thing starting a review on github.com does.
    /// GitHub allows one per viewer per pull request, so callers must serialize.
    static func createPendingReviewArgs(pullRequestNodeID: String) -> [String] {
        [
            "api", "graphql",
            "-f", """
            query=mutation($pullRequestId: ID!) {
              addPullRequestReview(input: { pullRequestId: $pullRequestId }) {
                pullRequestReview { id }
              }
            }
            """,
            "-f", "pullRequestId=\(pullRequestNodeID)"
        ]
    }

    /// `addPullRequestReviewThread`; anchors one pending comment the way the
    /// review API does (path + line + side) and returns the created thread.
    static func addPendingReviewCommentArgs(
        reviewNodeID: String,
        path: String,
        line: Int,
        side: PullRequestDiffSide,
        body: String
    ) -> [String] {
        [
            "api", "graphql",
            "-f", """
            query=mutation($reviewId: ID!, $path: String!, $line: Int!, $side: DiffSide!, $body: String!) {
              addPullRequestReviewThread(input: {
                pullRequestReviewId: $reviewId, path: $path, line: $line, side: $side, body: $body
              }) {
                thread { \(reviewThreadSelection) }
              }
            }
            """,
            "-f", "reviewId=\(reviewNodeID)",
            "-f", "path=\(path)",
            "-F", "line=\(line)",
            "-f", "side=\(side.rawValue)",
            "-f", "body=\(body)"
        ]
    }

    /// `updatePullRequestReviewComment`; pending comments are addressed by node
    /// id, unlike submitted ones which PATCH `pulls/comments/{id}`.
    static func updatePendingReviewCommentArgs(commentNodeID: String, body: String) -> [String] {
        [
            "api", "graphql",
            "-f", """
            query=mutation($commentId: ID!, $body: String!) {
              updatePullRequestReviewComment(
                input: { pullRequestReviewCommentId: $commentId, body: $body }
              ) { clientMutationId }
            }
            """,
            "-f", "commentId=\(commentNodeID)",
            "-f", "body=\(body)"
        ]
    }

    /// `deletePullRequestReviewComment`; takes the comment's node id as `id`.
    static func deletePendingReviewCommentArgs(commentNodeID: String) -> [String] {
        [
            "api", "graphql",
            "-f", """
            query=mutation($commentId: ID!) {
              deletePullRequestReviewComment(input: { id: $commentId }) { clientMutationId }
            }
            """,
            "-f", "commentId=\(commentNodeID)"
        ]
    }

    /// `deletePullRequestReview`; GitHub deletes *only* pending reviews.
    static func deletePendingReviewArgs(reviewNodeID: String) -> [String] {
        [
            "api", "graphql",
            "-f", """
            query=mutation($reviewId: ID!) {
              deletePullRequestReview(input: { pullRequestReviewId: $reviewId }) { clientMutationId }
            }
            """,
            "-f", "reviewId=\(reviewNodeID)"
        ]
    }

    /// `submitPullRequestReview`; publishes the pending review and every comment
    /// already attached to it, with the chosen verdict and summary body.
    static func submitPendingReviewArgs(
        reviewNodeID: String,
        event: PullRequestReviewEvent,
        body: String
    ) -> [String] {
        [
            "api", "graphql",
            "-f", """
            query=mutation($reviewId: ID!, $event: PullRequestReviewEvent!, $body: String) {
              submitPullRequestReview(
                input: { pullRequestReviewId: $reviewId, event: $event, body: $body }
              ) { clientMutationId }
            }
            """,
            "-f", "reviewId=\(reviewNodeID)",
            "-f", "event=\(event.rawValue)",
            "-f", "body=\(body)"
        ]
    }

    /// `resolveReviewThread` / `unresolveReviewThread`; both take the thread's node id.
    static func threadResolutionArgs(threadID: String, resolved: Bool) -> [String] {
        let mutation = resolved ? "resolveReviewThread" : "unresolveReviewThread"
        return [
            "api", "graphql",
            "-f", """
            query=mutation($threadId: ID!) {
              \(mutation)(input: { threadId: $threadId }) { clientMutationId }
            }
            """,
            "-f", "threadId=\(threadID)"
        ]
    }
}

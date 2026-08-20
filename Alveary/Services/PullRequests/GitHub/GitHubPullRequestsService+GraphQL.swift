import Foundation

// MARK: - Queries

extension GitHubPullRequestsService {
    /// One `-f` search string per requested bucket, in `allCases` order so the argument list
    /// and the document it accompanies stay deterministic.
    ///
    /// A bucket's `After` cursor is passed only when it has one. The variable is declared either
    /// way, so an omitted one arrives as null — GitHub's own "start at the first page" — and the
    /// document text stays identical between a first page and a resumed one.
    static func listArgs(
        buckets: Set<PullRequestInvolvementBucket>,
        status: PullRequestStatus?,
        options: PullRequestListOptions
    ) -> [String] {
        let ordered = orderedBuckets(buckets)
        var args = ["api", "graphql", "-f", "query=\(listQuery(buckets: ordered, pageSize: options.resolvedPageSize))"]
        for bucket in ordered {
            let name = bucket.queryVariableName
            let query = bucket.searchQuery(
                status: status,
                updatedAfter: options.updatedAfter,
                updatedBefore: options.updatedBefore
            )
            args += ["-f", "\(name)=\(query)"]
            if let cursor = options.cursors[bucket] {
                args += ["-f", "\(name)After=\(cursor)"]
            }
        }
        return args
    }

    static func orderedBuckets(_ buckets: Set<PullRequestInvolvementBucket>) -> [PullRequestInvolvementBucket] {
        PullRequestInvolvementBucket.allCases.filter(buckets.contains)
    }

    /// `addReaction` / `removeReaction` GraphQL mutations; both take the subject's
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

    // One aliased `search` per requested bucket. Every leg names exactly one bucket — see the
    // never-batch bullet in `Alveary/Services/PullRequests/GitHub/AGENTS.md` — so this renders a single search in
    // practice; the loop remains because the shape is per bucket.
    //
    // `edges { cursor node }` rather than `nodes`: a per-row cursor is what lets a caller that
    // emitted only a prefix of a page resume from that row instead of skipping the rest.
    private static func listQuery(buckets: [PullRequestInvolvementBucket], pageSize: Int) -> String {
        let variables = buckets
            .map { "$\($0.queryVariableName): String!, $\($0.queryVariableName)After: String" }
            .joined(separator: ", ")
        let searches = buckets.map { bucket in
            let name = bucket.queryVariableName
            return """
              \(name): search(type: ISSUE, query: $\(name), first: \(pageSize), after: $\(name)After) {
                edges { cursor node { ...pr } }
                pageInfo { endCursor hasNextPage }
              }
            """
        }
        return """
        query(\(variables)) {
        \(searches.joined(separator: "\n"))
        }
        \(listFragment)
        """
    }

    // Every field here is computed *per row*, which is what dominates this query's cost — so a
    // field the list does not render must not be here. Two are deliberately absent, both for the
    // same reason and both still fetched by the detail query:
    //
    // - `statusCheckRollup`, which makes GitHub's search slow and 502-prone.
    // - `reviewDecision`, measured at over half this query's cost on a large account: an 8,000-row
    //   involvement search ran 8.1s with it and 3.8s without, and both Reviewing legs together
    //   went 7.2s to 3.6s. Nothing renders it (the Overview shows the Reviewers list instead), and
    //   `get_pr` still carries it for the host tool.
    //
    // One constant so that invariant has a single place to hold.
    private static let listFragment = """
    fragment pr on PullRequest {
      number title url state isDraft
      author { login avatarUrl(size: 64) }
      headRefName baseRefName updatedAt additions deletions
      repository { nameWithOwner }
    }
    """

    /// Shared by the detail query and `addPullRequestReviewThread`'s payload, so
    /// a thread created optimistically decodes exactly like a fetched one. Adding
    /// a field to only one of the two would leave freshly added pending comments
    /// missing state the rest of the UI reads.
    ///
    /// The comment page is deliberately large and carries `totalCount`. GitHub returns a
    /// thread's comments oldest-first, so a small page drops the *newest* replies — which is
    /// exactly where a thread says whether its point was already answered. 100 covers every
    /// realistic thread, and `totalCount` keeps the count honest past it rather than reporting
    /// the page size as the total.
    private static let reviewThreadSelection = """
    id path line diffSide isResolved isOutdated
    comments(first: 100) {
      totalCount
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
          headRefName baseRefName headRefOid baseRefOid additions deletions changedFiles reviewDecision
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

    /// `convertPullRequestToDraft`; the inverse of `readyForReviewArgs`, and
    /// likewise GraphQL-only — REST cannot put a pull request back into draft.
    static func convertToDraftArgs(nodeID: String) -> [String] {
        [
            "api", "graphql",
            "-f", """
            query=mutation($pullRequestId: ID!) {
              convertPullRequestToDraft(input: { pullRequestId: $pullRequestId }) { clientMutationId }
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

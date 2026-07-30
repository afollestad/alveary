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

    private static let detailQuery = """
    query($owner: String!, $name: String!, $number: Int!) {
      viewer { login avatarUrl(size: 64) }
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          id number title url state isDraft body createdAt updatedAt
          reactionGroups { content viewerHasReacted reactors { totalCount } }
          author { login avatarUrl(size: 64) }
          headRefName baseRefName additions deletions changedFiles reviewDecision
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
              id author { __typename login avatarUrl(size: 64) } body createdAt
              reactionGroups { content viewerHasReacted reactors { totalCount } }
            }
          }
          reviews(first: 50) {
            nodes {
              id author { __typename login avatarUrl(size: 64) } state body submittedAt
              reactionGroups { content viewerHasReacted reactors { totalCount } }
            }
          }
          reviewThreads(first: 100) {
            nodes {
              id path line diffSide isResolved isOutdated
              comments(first: 20) {
                nodes {
                  id databaseId viewerCanUpdate viewerCanDelete diffHunk
                  author { __typename login avatarUrl(size: 64) } body createdAt
                  reactionGroups { content viewerHasReacted reactors { totalCount } }
                }
              }
            }
          }
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

// MARK: - Mapping

extension GitHubPullRequestsService {
    static func makeListResult(data: ListGraphQLData, warnings: [String]) -> PullRequestListResult {
        let buckets: [(SearchBucketNode?, PullRequestInvolvementBucket)] = [
            (data.authored, .authored),
            (data.requested, .reviewRequested),
            (data.reviewed, .reviewed)
        ]
        let bucketSummaries = buckets.map { node, bucket in
            (node?.nodes ?? []).compactMap { node -> PullRequestSummary? in
                guard let node, var summary = makeSummary(from: node) else {
                    return nil
                }
                switch bucket {
                case .authored:
                    summary.isAuthored = true
                case .reviewRequested:
                    summary.isReviewRequested = true
                case .reviewed:
                    summary.hasReviewed = true
                }
                return summary
            }
        }
        return PullRequestListResult(summaries: PullRequestListMerge.merge(bucketSummaries), warnings: warnings)
    }

    static func makeSummary(from node: PullRequestListNode) -> PullRequestSummary? {
        guard let number = node.number,
              let nameWithOwner = node.repository?.nameWithOwner,
              let id = PullRequestIdentifier(nameWithOwner: nameWithOwner, number: number),
              let title = node.title,
              let state = node.state,
              let updatedAt = node.updatedAt else {
            return nil
        }
        return PullRequestSummary(
            id: id,
            title: title,
            url: node.url.flatMap(URL.init(string:)),
            status: makeStatus(state: state, isDraft: node.isDraft ?? false),
            authorLogin: node.author?.login ?? "ghost",
            authorAvatarURL: node.author?.avatarUrl.flatMap(URL.init(string:)),
            headRefName: node.headRefName ?? "",
            baseRefName: node.baseRefName ?? "",
            updatedAt: updatedAt,
            additions: node.additions ?? 0,
            deletions: node.deletions ?? 0,
            reviewDecision: node.reviewDecision,
            isAuthored: false,
            isReviewRequested: false,
            hasReviewed: false
        )
    }

    static func makeDetail(
        id: PullRequestIdentifier,
        node: PullRequestDetailNode,
        viewer: GraphQLActorNode? = nil
    ) -> PullRequestDetail {
        let rollup = node.commits?.nodes?.first??.commit?.statusCheckRollup
        return PullRequestDetail(
            id: id,
            title: node.title ?? "",
            url: node.url.flatMap(URL.init(string:)),
            status: makeStatus(state: node.state ?? "OPEN", isDraft: node.isDraft ?? false),
            authorLogin: node.author?.login ?? "ghost",
            authorAvatarURL: node.author?.avatarUrl.flatMap(URL.init(string:)),
            headRefName: node.headRefName ?? "",
            baseRefName: node.baseRefName ?? "",
            createdAt: node.createdAt,
            updatedAt: node.updatedAt,
            additions: node.additions ?? 0,
            deletions: node.deletions ?? 0,
            changedFiles: node.changedFiles ?? 0,
            bodyMarkdown: node.body ?? "",
            reviewDecision: node.reviewDecision,
            checks: makeChecks(from: rollup),
            comments: makeComments(from: node.comments),
            reviews: makeReviews(from: node.reviews),
            reviewThreads: makeReviewThreads(from: node.reviewThreads),
            timelineEvents: makeTimelineEvents(from: node.timelineItems),
            reviewers: makeReviewers(
                requests: node.reviewRequests,
                reviews: makeReviews(from: node.reviews),
                pullRequestAuthor: node.author?.login
            ),
            nodeID: node.id,
            reactions: makeReactions(from: node.reactionGroups),
            viewerLogin: viewer?.login,
            viewerAvatarURL: viewer?.avatarUrl.flatMap(URL.init(string:))
        )
    }

    static func makeStatus(state: String, isDraft: Bool) -> PullRequestStatus {
        switch state {
        case "MERGED":
            return .merged
        case "CLOSED":
            return .closed
        default:
            return isDraft ? .draft : .open
        }
    }

    static func makeChecks(from rollup: GraphQLRollupNode?) -> [PullRequestCheck] {
        (rollup?.contexts?.nodes ?? []).compactMap { node in
            guard let node else {
                return nil
            }
            return makeCheck(from: node)
        }
    }

    static func makeCheck(from node: GraphQLCheckContextNode) -> PullRequestCheck? {
        if let name = node.name {
            // CheckRun: `status` is QUEUED/IN_PROGRESS/COMPLETED; `conclusion` only exists once completed.
            let state: PullRequestChecksState
            if node.status != "COMPLETED" {
                state = .pending
            } else {
                switch node.conclusion {
                case "SUCCESS", "NEUTRAL", "SKIPPED":
                    state = .passing
                default:
                    state = .failing
                }
            }
            return PullRequestCheck(name: name, state: state, detailsURL: node.detailsUrl.flatMap(URL.init(string:)))
        }
        if let context = node.context {
            let state: PullRequestChecksState
            switch node.state {
            case "SUCCESS":
                state = .passing
            case "PENDING", "EXPECTED":
                state = .pending
            default:
                state = .failing
            }
            return PullRequestCheck(name: context, state: state, detailsURL: node.targetUrl.flatMap(URL.init(string:)))
        }
        return nil
    }

    static func makeComments(from node: GraphQLCommentsNode?) -> [PullRequestComment] {
        (node?.nodes ?? []).compactMap { comment in
            guard let comment else {
                return nil
            }
            return PullRequestComment(
                authorLogin: comment.author?.login ?? "ghost",
                authorAvatarURL: comment.author?.avatarUrl.flatMap(URL.init(string:)),
                bodyMarkdown: comment.body ?? "",
                createdAt: comment.createdAt,
                databaseId: comment.databaseId,
                nodeID: comment.id,
                viewerCanUpdate: comment.viewerCanUpdate ?? false,
                viewerCanDelete: comment.viewerCanDelete ?? false,
                reactions: makeReactions(from: comment.reactionGroups),
                isBot: comment.author?.typeName == "Bot"
            )
        }
    }

    /// Empty groups drop out; order follows GitHub's fixed palette.
    static func makeReactions(from groups: [GraphQLReactionGroupNode?]?) -> [PullRequestCommentReaction] {
        (groups ?? []).compactMap { group -> PullRequestCommentReaction? in
            guard let group,
                  let content = group.content.flatMap(PullRequestReactionContent.init(rawValue:)),
                  let count = group.reactors?.totalCount,
                  count > 0 else {
                return nil
            }
            return PullRequestCommentReaction(
                content: content,
                count: count,
                viewerHasReacted: group.viewerHasReacted ?? false
            )
        }
    }

    static func makeReviews(from node: GraphQLReviewsNode?) -> [PullRequestReview] {
        (node?.nodes ?? []).compactMap { review in
            guard let review else {
                return nil
            }
            return PullRequestReview(
                authorLogin: review.author?.login ?? "ghost",
                authorAvatarURL: review.author?.avatarUrl.flatMap(URL.init(string:)),
                state: review.state.flatMap(PullRequestReviewState.init(rawValue:)) ?? .commented,
                bodyMarkdown: review.body ?? "",
                submittedAt: review.submittedAt,
                nodeID: review.id,
                reactions: makeReactions(from: review.reactionGroups),
                isBot: review.author?.typeName == "Bot"
            )
        }
    }

    /// The tail of the thread's diff hunk — the lines closest to the commented line —
    /// so Activity can show what code the thread anchors to.
    static func diffHunkExcerpt(_ diffHunk: String?, maxLines: Int = 4) -> String? {
        guard let diffHunk, !diffHunk.isEmpty else {
            return nil
        }
        let lines = diffHunk
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("@@") }
        guard !lines.isEmpty else {
            return nil
        }
        return lines.suffix(maxLines).joined(separator: "\n")
    }

    static func makeReviewThreads(from node: GraphQLReviewThreadsNode?) -> [PullRequestReviewThread] {
        (node?.nodes ?? []).compactMap { thread in
            guard let thread, let path = thread.path else {
                return nil
            }
            return PullRequestReviewThread(
                path: path,
                line: thread.line,
                side: thread.diffSide.flatMap(PullRequestDiffSide.init(rawValue:)) ?? .right,
                isResolved: thread.isResolved ?? false,
                isOutdated: thread.isOutdated ?? false,
                comments: makeComments(from: thread.comments),
                diffHunkExcerpt: diffHunkExcerpt(thread.comments?.nodes?.first??.diffHunk),
                nodeID: thread.id
            )
        }
    }

    /// Pending requests first, then each past reviewer's latest verdict — the same
    /// composition GitHub's Reviewers sidebar shows. The PR author never appears,
    /// and only reviewers with a submitted review offer re-request.
    static func makeReviewers(
        requests: GraphQLReviewRequestsNode?,
        reviews: [PullRequestReview],
        pullRequestAuthor: String?
    ) -> [PullRequestReviewer] {
        var reviewers: [PullRequestReviewer] = []
        var seen = Set<String>()
        for request in requests?.nodes ?? [] {
            guard let reviewer = request?.requestedReviewer,
                  let login = reviewer.login ?? reviewer.name,
                  seen.insert(login).inserted else {
                continue
            }
            reviewers.append(PullRequestReviewer(
                login: login,
                avatarURL: reviewer.avatarUrl.flatMap(URL.init(string:)),
                isBot: reviewer.typeName == "Bot",
                state: .requested,
                canReRequest: false
            ))
        }
        // Latest submitted verdict per author, in submission order.
        var latestByAuthor: [String: PullRequestReview] = [:]
        for review in reviews where review.state != .pending {
            latestByAuthor[review.authorLogin] = review
        }
        for review in reviews {
            guard let latest = latestByAuthor.removeValue(forKey: review.authorLogin),
                  latest.authorLogin != pullRequestAuthor,
                  seen.insert(latest.authorLogin).inserted else {
                continue
            }
            let state: PullRequestReviewer.State
            switch latest.state {
            case .approved:
                state = .approved
            case .changesRequested:
                state = .changesRequested
            case .commented, .dismissed, .pending:
                state = .commented
            }
            reviewers.append(PullRequestReviewer(
                login: latest.authorLogin,
                avatarURL: latest.authorAvatarURL,
                isBot: latest.isBot,
                state: state,
                // GitHub offers re-request only for human reviewers; app/bot
                // reviews (Copilot, Codex) cannot go through `requested_reviewers`.
                canReRequest: !latest.isBot
            ))
        }
        return reviewers
    }
}

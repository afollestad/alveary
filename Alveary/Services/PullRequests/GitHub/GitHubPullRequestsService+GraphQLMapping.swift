import Foundation

// Maps the decoded GraphQL node shapes from
// `GitHubPullRequestsService+GraphQLNodes.swift` onto the domain models the
// app renders. The queries themselves live in
// `GitHubPullRequestsService+GraphQL.swift`.
extension GitHubPullRequestsService {
    /// Keys the result by the buckets that were *requested*, not the ones that came back with
    /// nodes: a SAML-forbidden bucket decodes as `null` and must still read as loaded-and-empty,
    /// or the caller would treat it as never fetched and ask again on every pass.
    static func makeListResult(
        data: ListGraphQLData,
        warnings: [String],
        buckets: Set<PullRequestInvolvementBucket>
    ) -> PullRequestListResult {
        var summariesByBucket: [PullRequestInvolvementBucket: [PullRequestSummary]] = [:]
        var pageInfoByBucket: [PullRequestInvolvementBucket: PullRequestListPageInfo] = [:]
        for bucket in orderedBuckets(buckets) {
            let page = makePage(from: node(for: bucket, in: data), bucket: bucket)
            summariesByBucket[bucket] = page.summaries
            pageInfoByBucket[bucket] = page.pageInfo
        }
        return PullRequestListResult(
            summariesByBucket: summariesByBucket,
            warnings: warnings,
            pageInfoByBucket: pageInfoByBucket
        )
    }

    /// Folds the legs of a fan-out list fetch into the single result the caller asked for.
    ///
    /// `pageInfoByBucket` unions exactly like `summariesByBucket`, so a failed bucket has no page
    /// info either and a caller building a resume token cannot advance past a page it never saw.
    ///
    /// A bucket that *failed* is absent from `summariesByBucket`, which is what distinguishes it
    /// from a SAML-forbidden one — that decodes as null and stays keyed as loaded-and-empty, since
    /// the caller must not refetch it forever. Every failure is also named in `warnings`, so a
    /// caller that only reads those still learns the answer is short a bucket.
    ///
    /// Only every leg failing throws, and then with the first failure in `allCases` order so which
    /// leg finished first cannot change the error the caller sees.
    static func mergeBucketOutcomes(
        _ outcomes: [PullRequestInvolvementBucket: PullRequestBucketOutcome]
    ) throws -> PullRequestListResult {
        var summariesByBucket: [PullRequestInvolvementBucket: [PullRequestSummary]] = [:]
        var pageInfoByBucket: [PullRequestInvolvementBucket: PullRequestListPageInfo] = [:]
        var warnings: [String] = []
        var failures: [(bucket: PullRequestInvolvementBucket, error: PullRequestsServiceError)] = []
        var succeeded = false
        for bucket in PullRequestInvolvementBucket.allCases {
            switch outcomes[bucket] {
            case .success(let result):
                succeeded = true
                summariesByBucket.merge(result.summariesByBucket) { _, leg in leg }
                pageInfoByBucket.merge(result.pageInfoByBucket) { _, leg in leg }
                // Every leg carries the same SAML message, so without this a three-bucket call
                // would report it three times.
                for warning in result.warnings where !warnings.contains(warning) {
                    warnings.append(warning)
                }
            case .failure(let error):
                failures.append((bucket, error))
            case nil:
                continue
            }
        }
        if !succeeded, let failure = failures.first {
            throw failure.error
        }
        for failure in failures {
            warnings.append(
                "Could not load \(failure.bucket.involvementDisplayName) pull requests: "
                    + failure.error.localizedDescription
            )
        }
        return PullRequestListResult(
            summariesByBucket: summariesByBucket,
            warnings: warnings,
            pageInfoByBucket: pageInfoByBucket
        )
    }

    private static func node(for bucket: PullRequestInvolvementBucket, in data: ListGraphQLData) -> SearchBucketNode? {
        switch bucket {
        case .authored:
            return data.authored
        case .reviewRequested:
            return data.requested
        case .reviewed:
            return data.reviewed
        }
    }

    /// One bucket's rows beside the cursors that resume them.
    ///
    /// An edge that maps to no summary — a SAML `null`, or a non-PR search hit — contributes
    /// neither a summary nor a row cursor, which is what keeps the two arrays aligned
    /// index-for-index. A missing `pageInfo` (the SAML-forbidden bucket, which decodes as null
    /// throughout) reads as exhausted rather than as more-pages-unknown, so a caller cannot page
    /// a bucket GitHub will never answer.
    private static func makePage(
        from node: SearchBucketNode?,
        bucket: PullRequestInvolvementBucket
    ) -> (summaries: [PullRequestSummary], pageInfo: PullRequestListPageInfo) {
        var summaries: [PullRequestSummary] = []
        var rowCursors: [String] = []
        for edge in node?.edges ?? [] {
            guard let edge, let listNode = edge.node, var summary = makeSummary(from: listNode) else {
                continue
            }
            switch bucket {
            case .authored:
                summary.isAuthored = true
            case .reviewRequested:
                summary.isReviewRequested = true
            case .reviewed:
                summary.hasReviewed = true
            }
            summaries.append(summary)
            rowCursors.append(edge.cursor ?? "")
        }
        guard let pageInfo = node?.pageInfo else {
            return (summaries, PullRequestListPageInfo(endCursor: nil, hasNextPage: false, rowCursors: rowCursors))
        }
        return (
            summaries,
            PullRequestListPageInfo(
                endCursor: pageInfo.endCursor,
                hasNextPage: pageInfo.hasNextPage ?? false,
                rowCursors: rowCursors
            )
        )
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
            viewerAvatarURL: viewer?.avatarUrl.flatMap(URL.init(string:)),
            viewerCanUpdate: node.viewerCanUpdate ?? false,
            headRefExists: node.headRef != nil,
            pendingReviewNodeID: node.pendingReview?.nodes?.first??.id,
            headRefOid: node.headRefOid,
            baseRefOid: node.baseRefOid
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

    /// Collapses the rollup the way github.com does: one row per (job name, workflow) for check
    /// runs, one per context for legacy commit statuses.
    ///
    /// `statusCheckRollup.contexts` carries *every* check run on the head commit, superseded ones
    /// included. A workflow that re-triggers — on `pull_request_review`, say — mints a fresh check
    /// suite each time, so a workflow that ran six times contributes six nodes per job. Rendering
    /// them 1:1 is what put six identical `Release` rows in the pane against github.com's one.
    ///
    /// The survivor is the newest *run*, keyed on `checkSuite.workflowRun.databaseId` — **never on
    /// `startedAt`/`completedAt`, which do not order the runs.** A job in a later run routinely
    /// starts before one in an earlier run, and a skipped run can report `completedAt` ahead of its
    /// own `startedAt`; sorting by time picks a stale run and links the row to the wrong job. The
    /// check run's own `databaseId` breaks the remaining tie when a single job is re-run inside one
    /// workflow run, which keeps the run id but mints a new check run. A commit status has neither
    /// id, so it falls back to `createdAt`.
    static func makeChecks(from rollup: GraphQLRollupNode?) -> [PullRequestCheck] {
        var winners: [String: (check: PullRequestCheck, rank: CheckRollupRank)] = [:]
        for case let node? in rollup?.contexts?.nodes ?? [] {
            guard let check = makeCheck(from: node) else {
                continue
            }
            // A check run and a commit status may share a display name without being the same
            // check, so they never collapse into each other.
            let key = "\(node.name == nil ? "status" : "run")\u{0}\(check.id)"
            let rank = CheckRollupRank(node: node)
            if let existing = winners[key], rank <= existing.rank {
                continue
            }
            winners[key] = (check, rank)
        }
        // Alphabetical, as github.com orders the list. Dictionary order is not stable across
        // runs, so without this the deduped rows would shuffle between refreshes.
        return winners.values.map(\.check).sorted { lhs, rhs in
            let ordering = lhs.displayName.caseInsensitiveCompare(rhs.displayName)
            return ordering == .orderedSame ? lhs.id < rhs.id : ordering == .orderedAscending
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
            return PullRequestCheck(
                name: name,
                // The workflow names the run; an app that posts checks outside Actions (Graphite,
                // for one) has no workflow run, and its own name is the label github.com shows.
                workflowName: node.checkSuite?.workflowRun?.workflow?.name ?? node.checkSuite?.app?.name,
                state: state,
                detailsURL: node.detailsUrl.flatMap(URL.init(string:))
            )
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
                isBot: comment.author?.typeName == "Bot",
                // Only review-thread comments carry `state`; top-level
                // conversation comments have no pending concept at all.
                isPending: comment.state == "PENDING"
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

    /// The viewer's own PENDING review is dropped: it is a draft, not activity,
    /// so it must never render as a timeline review card or a reviewer verdict.
    /// Its threads still come through `reviewThreads`, badged pending.
    static func makeReviews(from node: GraphQLReviewsNode?) -> [PullRequestReview] {
        (node?.nodes ?? []).compactMap { review in
            guard let review, review.state != PullRequestReviewState.pending.rawValue else {
                return nil
            }
            return PullRequestReview(
                authorLogin: review.author?.login ?? "ghost",
                authorAvatarURL: review.author?.avatarUrl.flatMap(URL.init(string:)),
                state: review.state.flatMap(PullRequestReviewState.init(rawValue:)) ?? .commented,
                bodyMarkdown: review.body ?? "",
                submittedAt: review.submittedAt,
                databaseId: review.databaseId,
                nodeID: review.id,
                viewerCanUpdate: review.viewerCanUpdate ?? false,
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
        (node?.nodes ?? []).compactMap(makeReviewThread(from:))
    }

    /// One thread, shared by the detail query and `addPullRequestReviewThread`'s
    /// payload so a freshly created pending thread is shaped like a fetched one.
    static func makeReviewThread(from thread: GraphQLReviewThreadNode?) -> PullRequestReviewThread? {
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
            nodeID: thread.id,
            reviewNodeID: thread.comments?.nodes?.first??.pullRequestReview?.id,
            totalCommentCount: thread.comments?.totalCount
        )
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

/// Orders the rollup's repeats of one check so the newest wins. See `makeChecks` for why this
/// leads with run ids rather than the timestamps the nodes also carry.
private struct CheckRollupRank: Comparable {
    let workflowRunID: Int
    let checkRunID: Int
    let postedAt: Date

    init(node: GraphQLCheckContextNode) {
        workflowRunID = node.checkSuite?.workflowRun?.databaseId ?? 0
        checkRunID = node.databaseId ?? 0
        postedAt = node.createdAt ?? .distantPast
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.workflowRunID, lhs.checkRunID, lhs.postedAt) < (rhs.workflowRunID, rhs.checkRunID, rhs.postedAt)
    }
}

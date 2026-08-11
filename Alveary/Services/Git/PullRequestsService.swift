import Foundation

struct PullRequestIdentifier: Hashable, Sendable, Codable {
    let owner: String
    let repo: String
    let number: Int

    init(owner: String, repo: String, number: Int) {
        self.owner = owner
        self.repo = repo
        self.number = number
    }

    init?(nameWithOwner: String, number: Int) {
        let parts = nameWithOwner.split(separator: "/")
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            return nil
        }
        self.init(owner: String(parts[0]), repo: String(parts[1]), number: number)
    }

    var nameWithOwner: String {
        "\(owner)/\(repo)"
    }

    var displayKey: String {
        "\(nameWithOwner)#\(number)"
    }
}

// String-backed so persisted copies (settings filters, the list cache) stay readable, and
// `CaseIterable` so the `list_involved_prs` schema and its refusals name the same set the search
// can actually run.
enum PullRequestStatus: String, Sendable, Hashable, CaseIterable, Codable {
    case open
    case draft
    case merged
    case closed

    /// GitHub search qualifiers narrowing a bucket to this status. The screen's status
    /// filter is single-select because these cannot be combined: GitHub search has no
    /// `OR`, so `is:open is:merged` ANDs down to zero results.
    var searchQualifier: String {
        switch self {
        case .open:
            // Drafts are open pull requests, so excluding them takes its own qualifier.
            return "is:open draft:false"
        case .draft:
            // `.draft` here means open *and* draft; a closed draft maps to `.closed`.
            return "is:open draft:true"
        case .merged:
            return "is:merged"
        case .closed:
            // `is:closed` alone counts merged pull requests as closed.
            return "is:closed is:unmerged"
        }
    }
}

/// The Pull Requests screen's status selection, persisted in `AppSettings` and pushed into the
/// GitHub search. Single-select — and so an enum carrying its own `all` case rather than an
/// optional — for two reasons: GitHub search qualifiers only AND, so `is:open is:merged` matches
/// nothing, and `AppSettings` encodes synthesized, which would drop a nil optional's key entirely
/// and make an explicit "All" indistinguishable from a fresh install.
enum PullRequestStatusFilter: String, Sendable, Hashable, CaseIterable, Codable {
    case all
    case open
    case draft
    case merged
    case closed

    init(_ status: PullRequestStatus?) {
        switch status {
        case .none: self = .all
        case .open: self = .open
        case .draft: self = .draft
        case .merged: self = .merged
        case .closed: self = .closed
        }
    }

    /// nil for `all`, which searches every state.
    var status: PullRequestStatus? {
        switch self {
        case .all: return nil
        case .open: return .open
        case .draft: return .draft
        case .merged: return .merged
        case .closed: return .closed
        }
    }

    func matches(_ status: PullRequestStatus) -> Bool {
        self.status == nil || self.status == status
    }
}

enum PullRequestChecksState: Sendable, Equatable {
    case passing
    case failing
    case pending
}

enum PullRequestDiffSide: String, Sendable, Equatable, Codable {
    case left = "LEFT"
    case right = "RIGHT"
}

/// Codable so the last fetched list can persist across launches for instant first paint.
struct PullRequestSummary: Identifiable, Equatable, Sendable, Codable {
    let id: PullRequestIdentifier
    let title: String
    let url: URL?
    /// Mutable so closing or reopening the pull request can update the row in
    /// place without waiting for the next list fetch.
    var status: PullRequestStatus
    let authorLogin: String
    let authorAvatarURL: URL?
    let headRefName: String
    let baseRefName: String
    let updatedAt: Date
    let additions: Int
    let deletions: Int
    let reviewDecision: String?
    var isAuthored: Bool
    var isReviewRequested: Bool
    var hasReviewed: Bool

    var repositoryNameWithOwner: String {
        id.nameWithOwner
    }

    var belongsToAnyBucket: Bool {
        isAuthored || isReviewRequested || hasReviewed
    }

    /// Which search bucket produced this summary. A pull request can belong to several —
    /// `PullRequestListMerge` ORs the flags together when the buckets are merged.
    func belongs(to bucket: PullRequestInvolvementBucket) -> Bool {
        switch bucket {
        case .authored:
            return isAuthored
        case .reviewRequested:
            return isReviewRequested
        case .reviewed:
            return hasReviewed
        }
    }
}

/// One involvement search bucket. Callers ask for the buckets the visible tab renders and each
/// one is searched by its own request; see the fetch bullets in `Alveary/Services/Git/AGENTS.md`.
///
/// String-backed so the list cache can key its stored buckets readably.
enum PullRequestInvolvementBucket: String, Sendable, Hashable, CaseIterable, Codable {
    case authored
    case reviewRequested = "requested"
    case reviewed

    /// GraphQL variable name and `search` alias. One source for both so a renamed case
    /// cannot leave the document and the `-f` arguments disagreeing.
    var queryVariableName: String {
        rawValue
    }

    /// Names the involvement in a warning about a bucket that could not be loaded; `rawValue`
    /// would say "requested", which reads as a truncated sentence rather than an involvement.
    var involvementDisplayName: String {
        switch self {
        case .authored:
            return "authored"
        case .reviewRequested:
            return "review-requested"
        case .reviewed:
            return "reviewed"
        }
    }

    /// `status` nil searches every state, which is GitHub's own default. The `updated:` bounds are
    /// day-granular in UTC, which is the granularity `PullRequestSearchDates` and the host tool's
    /// input schema both advertise; nil leaves the bucket unbounded in that direction.
    func searchQuery(
        status: PullRequestStatus?,
        updatedAfter: Date?,
        updatedBefore: Date?
    ) -> String {
        [
            "is:pr",
            status?.searchQualifier,
            involvementQualifier,
            updatedAfter.map { "updated:>=\(PullRequestSearchDates.day($0))" },
            updatedBefore.map { "updated:<=\(PullRequestSearchDates.day($0))" },
            "sort:updated-desc"
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    private var involvementQualifier: String {
        switch self {
        case .authored:
            return "author:@me"
        case .reviewRequested:
            return "review-requested:@me"
        case .reviewed:
            return "reviewed-by:@me"
        }
    }
}

enum PullRequestListMerge {
    /// Merges bucket results by identifier, OR-ing involvement flags. The entry with
    /// the newest `updatedAt` supplies the field values; output sorts newest first.
    static func merge(_ buckets: [[PullRequestSummary]]) -> [PullRequestSummary] {
        var byID = [PullRequestIdentifier: PullRequestSummary]()
        for bucket in buckets {
            for summary in bucket {
                guard let existing = byID[summary.id] else {
                    byID[summary.id] = summary
                    continue
                }
                var merged = summary.updatedAt >= existing.updatedAt ? summary : existing
                merged.isAuthored = existing.isAuthored || summary.isAuthored
                merged.isReviewRequested = existing.isReviewRequested || summary.isReviewRequested
                merged.hasReviewed = existing.hasReviewed || summary.hasReviewed
                byID[summary.id] = merged
            }
        }
        return byID.values.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id.displayKey < rhs.id.displayKey
        }
    }
}

/// A successful list fetch. `warnings` carries non-fatal GraphQL errors — for example
/// SAML-protected organizations return `FORBIDDEN` per-node errors alongside valid data.
struct PullRequestListResult: Equatable, Sendable {
    /// Only the buckets the caller asked for; the view model stores these separately so a
    /// tab can reuse a bucket another tab already loaded.
    let summariesByBucket: [PullRequestInvolvementBucket: [PullRequestSummary]]
    let warnings: [String]
    /// Where each requested bucket's page ended, keyed exactly like `summariesByBucket`. A bucket
    /// absent here was never fetched or its leg failed; one present with `hasNextPage` false is
    /// fully drained.
    let pageInfoByBucket: [PullRequestInvolvementBucket: PullRequestListPageInfo]
    /// The buckets merged into one list, so callers wanting the flat view do not each repeat it.
    let summaries: [PullRequestSummary]

    init(
        summariesByBucket: [PullRequestInvolvementBucket: [PullRequestSummary]],
        warnings: [String],
        pageInfoByBucket: [PullRequestInvolvementBucket: PullRequestListPageInfo] = [:]
    ) {
        self.summariesByBucket = summariesByBucket
        self.warnings = warnings
        self.pageInfoByBucket = pageInfoByBucket
        // `allCases` order rather than the dictionary's: `merge` lets the newest entry supply
        // field values and resolves `updatedAt` ties by iteration order, so feeding it an
        // unordered sequence would make the merged list nondeterministic.
        self.summaries = PullRequestListMerge.merge(
            PullRequestInvolvementBucket.allCases.compactMap { summariesByBucket[$0] }
        )
    }

    /// For test fixtures that start from already-merged summaries; `summaries` is kept exactly as
    /// given and the buckets are derived from each one's involvement flags.
    ///
    /// A summary carrying no flag falls into `.authored`. Nothing in production can produce one —
    /// `makeListResult` sets a flag per bucket — but a fixture built without them would otherwise
    /// belong to no bucket and vanish from a list assembled bucket by bucket.
    init(
        summaries: [PullRequestSummary],
        warnings: [String],
        pageInfoByBucket: [PullRequestInvolvementBucket: PullRequestListPageInfo] = [:]
    ) {
        self.summaries = summaries
        self.warnings = warnings
        self.pageInfoByBucket = pageInfoByBucket
        self.summariesByBucket = Dictionary(
            uniqueKeysWithValues: PullRequestInvolvementBucket.allCases.map { bucket in
                (bucket, summaries.filter {
                    $0.belongs(to: bucket) || (bucket == .authored && !$0.belongsToAnyBucket)
                })
            }
        )
    }
}

/// One bucket's fetch outcome. Carries the concrete error type rather than `any Error` because
/// these cross task-group boundaries — in the service's own fan-out and in the screen's — and so
/// have to be `Sendable`; the mapping happens in the child task.
typealias PullRequestBucketOutcome = Result<PullRequestListResult, PullRequestsServiceError>

enum PullRequestReviewEvent: String, Sendable, Equatable {
    case approve = "APPROVE"
    case requestChanges = "REQUEST_CHANGES"
    case comment = "COMMENT"
}

enum PullRequestsServiceError: Error, Sendable, Equatable {
    case ghNotInstalled
    case notAuthenticated
    case rateLimited
    case requestFailed(statusCode: Int)
    case responseTooLarge
    case decodingFailed(String)
    /// GitHub refused the query as too expensive to run, rather than failing to run it. It
    /// arrives as a GraphQL body error with no HTTP status, so it would otherwise land in
    /// `.transport` and surface GitHub's own sentence verbatim to the user. Retrying is
    /// pointless — the same query costs the same next time — so the remedy is a cheaper query.
    case queryTooExpensive
    case transport(String)
}

extension PullRequestsServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .ghNotInstalled:
            return "GitHub CLI (gh) is not installed"
        case .notAuthenticated:
            return "GitHub CLI is not authenticated"
        case .rateLimited:
            return "GitHub API rate limit exceeded"
        case .requestFailed(let statusCode):
            return "GitHub request failed with HTTP \(statusCode)"
        case .responseTooLarge:
            return "GitHub response exceeded the size limit"
        case .decodingFailed(let message):
            return "Unable to read the GitHub response: \(message)"
        case .queryTooExpensive:
            return "This GitHub search is too large for GitHub to complete"
        case .transport(let message):
            return message
        }
    }
}

protocol PullRequestsService: Sendable {
    /// Lists pull requests involving the authenticated user, one search per requested bucket.
    ///
    /// Callers ask only for the buckets they render, so a tab showing one involvement does not
    /// pay for the other two. `status` narrows every requested bucket the same way; nil searches
    /// every state. There is deliberately no defaulted overload — an implicit bucket set or
    /// status would let a call site silently fetch something other than what it displays.
    ///
    /// Several buckets degrade to a partial result: a bucket that failed is *absent* from
    /// `summariesByBucket` and named in `warnings`, and only every bucket failing throws.
    ///
    /// `options` carries the page size, per-bucket resume cursors, and `updated:` bounds;
    /// `.firstPage` is what every caller fetched before pagination existed.
    func listInvolvedPullRequests(
        buckets: Set<PullRequestInvolvementBucket>,
        status: PullRequestStatus?,
        options: PullRequestListOptions
    ) async throws -> PullRequestListResult
    func fetchDetail(_ id: PullRequestIdentifier) async throws -> PullRequestDetail
    /// Returns the raw unified diff for the pull request.
    func fetchDiff(_ id: PullRequestIdentifier) async throws -> String
    /// Posts a verdict and summary as a review of its own. Used only when the
    /// viewer has no pending review; otherwise `submitPendingReview` finishes
    /// that one, and its inline comments go with it.
    func submitReview(
        _ id: PullRequestIdentifier,
        event: PullRequestReviewEvent,
        body: String
    ) async throws
    /// Opens an empty PENDING review on the pull request and returns its node id.
    /// Omitting `event` is what leaves it pending, exactly like starting a review
    /// on github.com. Only one may exist per viewer per pull request.
    func createPendingReview(pullRequestNodeID: String) async throws -> String
    /// Adds one inline comment to the viewer's pending review as a new thread,
    /// returning the created thread so its ids can replace the optimistic copy.
    func addPendingReviewComment(
        reviewNodeID: String,
        path: String,
        line: Int,
        side: PullRequestDiffSide,
        body: String
    ) async throws -> PullRequestReviewThread
    /// Rewrites a pending comment. Addressed by GraphQL node id, unlike the
    /// REST-addressed `updateReviewComment` for submitted ones.
    func updatePendingReviewComment(commentNodeID: String, body: String) async throws
    /// Deletes a pending comment, addressed by GraphQL node id.
    func deletePendingReviewComment(commentNodeID: String) async throws
    /// Discards the viewer's whole pending review. Called once its last comment
    /// is deleted so no empty draft lingers on github.com.
    func deletePendingReview(reviewNodeID: String) async throws
    /// Submits the viewer's existing pending review with its verdict and summary,
    /// publishing every comment already attached to it.
    func submitPendingReview(
        reviewNodeID: String,
        event: PullRequestReviewEvent,
        body: String
    ) async throws
    /// Rewrites the body of an already-submitted review comment the viewer may update.
    func updateReviewComment(_ id: PullRequestIdentifier, commentID: Int, body: String) async throws
    /// Rewrites the summary body of an already-submitted review the viewer may
    /// update. There is no delete counterpart: GitHub only deletes pending reviews.
    func updateReview(_ id: PullRequestIdentifier, reviewID: Int, body: String) async throws
    /// Edits the pull request's own description. Gated by `viewerCanUpdate`.
    func updatePullRequestBody(_ id: PullRequestIdentifier, body: String) async throws
    /// Closes or reopens the pull request. Reopening requires the head branch to
    /// still exist; GitHub answers 422 otherwise.
    func setPullRequestClosed(_ id: PullRequestIdentifier, closed: Bool) async throws
    /// Takes a draft pull request out of draft. Addressed by GraphQL node id —
    /// GitHub exposes no REST endpoint for it.
    func markPullRequestReadyForReview(nodeID: String) async throws
    /// Puts an open pull request back into draft. Addressed by GraphQL node id
    /// for the same reason as its inverse: GitHub exposes no REST endpoint.
    func convertPullRequestToDraft(nodeID: String) async throws
    /// Permanently deletes an already-submitted review comment the viewer may delete.
    func deleteReviewComment(_ id: PullRequestIdentifier, commentID: Int) async throws
    /// Posts a new top-level conversation comment on the pull request.
    func addIssueComment(_ id: PullRequestIdentifier, body: String) async throws
    /// Rewrites the body of a top-level conversation comment the viewer may update.
    func updateIssueComment(_ id: PullRequestIdentifier, commentID: Int, body: String) async throws
    /// Permanently deletes a top-level conversation comment the viewer may delete.
    func deleteIssueComment(_ id: PullRequestIdentifier, commentID: Int) async throws
    /// Adds the viewer's reaction to a comment, addressed by GraphQL node id.
    func addReaction(subjectID: String, content: PullRequestReactionContent) async throws
    /// Removes the viewer's reaction from a comment, addressed by GraphQL node id.
    func removeReaction(subjectID: String, content: PullRequestReactionContent) async throws
    /// Replies to an existing review thread; `commentID` is the REST id of the
    /// thread's first comment.
    func replyToReviewComment(_ id: PullRequestIdentifier, commentID: Int, body: String) async throws
    /// Resolves or unresolves a review thread, addressed by GraphQL node id.
    func setReviewThreadResolved(threadID: String, resolved: Bool) async throws
    /// Requests (or re-requests) a review from a user by login.
    func requestReview(_ id: PullRequestIdentifier, reviewerLogin: String) async throws
    /// Opens a pull request from the branch checked out in `directory`,
    /// returning the created pull request's identifier.
    func createPullRequest(
        inDirectory directory: String,
        baseBranch: String,
        headBranch: String,
        title: String,
        body: String
    ) async throws -> PullRequestIdentifier
}

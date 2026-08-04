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

// String-backed so persisted copies (settings filters, the list cache) stay readable.
enum PullRequestStatus: String, Sendable, Hashable, Codable {
    case open
    case draft
    case merged
    case closed
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
}

/// One involvement search bucket of the batched list query.
enum PullRequestInvolvementBucket: Sendable {
    case authored
    case reviewRequested
    case reviewed

    var searchQuery: String {
        switch self {
        case .authored:
            return "is:pr author:@me sort:updated-desc"
        case .reviewRequested:
            return "is:pr review-requested:@me sort:updated-desc"
        case .reviewed:
            return "is:pr reviewed-by:@me sort:updated-desc"
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
    let summaries: [PullRequestSummary]
    let warnings: [String]
}

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
        case .transport(let message):
            return message
        }
    }
}

protocol PullRequestsService: Sendable {
    /// Lists pull requests involving the authenticated user — authored,
    /// review-requested, and reviewed — merged, in one batched request.
    func listInvolvedPullRequests() async throws -> PullRequestListResult
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

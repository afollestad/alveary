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
    let status: PullRequestStatus
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

struct PullRequestCheck: Equatable, Sendable {
    let name: String
    let state: PullRequestChecksState
    let detailsURL: URL?
}

/// GitHub's fixed reaction palette, in GitHub's picker order.
enum PullRequestReactionContent: String, CaseIterable, Sendable, Hashable {
    case thumbsUp = "THUMBS_UP"
    case thumbsDown = "THUMBS_DOWN"
    case laugh = "LAUGH"
    case hooray = "HOORAY"
    case confused = "CONFUSED"
    case heart = "HEART"
    case rocket = "ROCKET"
    case eyes = "EYES"

    var emoji: String {
        switch self {
        case .thumbsUp: return "👍"
        case .thumbsDown: return "👎"
        case .laugh: return "😄"
        case .hooray: return "🎉"
        case .confused: return "😕"
        case .heart: return "❤️"
        case .rocket: return "🚀"
        case .eyes: return "👀"
        }
    }
}

struct PullRequestCommentReaction: Equatable, Sendable, Hashable {
    let content: PullRequestReactionContent
    let count: Int
    let viewerHasReacted: Bool
}

struct PullRequestComment: Equatable, Sendable {
    let authorLogin: String
    let authorAvatarURL: URL?
    /// `var` so optimistic remote edits can rewrite it locally.
    var bodyMarkdown: String
    let createdAt: Date?
    /// REST id for review-thread comments; needed to edit a submitted comment.
    let databaseId: Int?
    /// GraphQL node id; the reaction mutations address the comment through it.
    let nodeID: String?
    /// Permission-based, not authorship-based: GitHub also lets collaborators with
    /// write access edit or delete other people's comments (`viewerCanUpdate` /
    /// `viewerCanDelete`).
    let viewerCanUpdate: Bool
    let viewerCanDelete: Bool
    /// Non-empty reaction groups only, in GitHub's palette order.
    var reactions: [PullRequestCommentReaction]
    /// GraphQL author `__typename == "Bot"`; drives the Bot pill.
    let isBot: Bool

    init(
        authorLogin: String,
        authorAvatarURL: URL?,
        bodyMarkdown: String,
        createdAt: Date?,
        databaseId: Int? = nil,
        nodeID: String? = nil,
        viewerCanUpdate: Bool = false,
        viewerCanDelete: Bool = false,
        reactions: [PullRequestCommentReaction] = [],
        isBot: Bool = false
    ) {
        self.authorLogin = authorLogin
        self.authorAvatarURL = authorAvatarURL
        self.bodyMarkdown = bodyMarkdown
        self.createdAt = createdAt
        self.databaseId = databaseId
        self.nodeID = nodeID
        self.viewerCanUpdate = viewerCanUpdate
        self.viewerCanDelete = viewerCanDelete
        self.reactions = reactions
        self.isBot = isBot
    }
}

enum PullRequestReviewState: String, Sendable, Equatable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case commented = "COMMENTED"
    case dismissed = "DISMISSED"
    case pending = "PENDING"
}

struct PullRequestReview: Equatable, Sendable {
    let authorLogin: String
    let authorAvatarURL: URL?
    let state: PullRequestReviewState
    let bodyMarkdown: String
    let submittedAt: Date?
    /// GraphQL node id; reviews take reactions like comments do.
    let nodeID: String?
    var reactions: [PullRequestCommentReaction]
    let isBot: Bool

    init(
        authorLogin: String,
        authorAvatarURL: URL?,
        state: PullRequestReviewState,
        bodyMarkdown: String,
        submittedAt: Date?,
        nodeID: String? = nil,
        reactions: [PullRequestCommentReaction] = [],
        isBot: Bool = false
    ) {
        self.authorLogin = authorLogin
        self.authorAvatarURL = authorAvatarURL
        self.state = state
        self.bodyMarkdown = bodyMarkdown
        self.submittedAt = submittedAt
        self.nodeID = nodeID
        self.reactions = reactions
        self.isBot = isBot
    }
}

struct PullRequestReviewThread: Equatable, Sendable {
    let path: String
    let line: Int?
    let side: PullRequestDiffSide
    var isResolved: Bool
    let isOutdated: Bool
    var comments: [PullRequestComment]
    /// The tail of the diff hunk the thread anchors to, for display context.
    let diffHunkExcerpt: String?
    /// GraphQL node id; resolve/unresolve mutations address the thread through it.
    let nodeID: String?

    init(
        path: String,
        line: Int?,
        side: PullRequestDiffSide,
        isResolved: Bool,
        isOutdated: Bool,
        comments: [PullRequestComment],
        diffHunkExcerpt: String? = nil,
        nodeID: String? = nil
    ) {
        self.path = path
        self.line = line
        self.side = side
        self.isResolved = isResolved
        self.isOutdated = isOutdated
        self.comments = comments
        self.diffHunkExcerpt = diffHunkExcerpt
        self.nodeID = nodeID
    }
}

/// One row of the Overview "Reviewers" list: a pending request or a past
/// reviewer's latest verdict.
struct PullRequestReviewer: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case requested
        case approved
        case changesRequested
        case commented
    }

    let login: String
    let avatarURL: URL?
    let isBot: Bool
    let state: State
    /// GitHub offers re-request only for reviewers with a submitted review who
    /// are not already requested again.
    let canReRequest: Bool
}

/// A bare timeline entry — GitHub's non-comment conversation rows: state
/// changes, pushed commits, force pushes, and review-request changes.
struct PullRequestTimelineEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case readyForReview
        case convertToDraft
        case closed
        case reopened
        case merged
        /// A commit pushed to the head branch; `detail` carries "sha headline".
        case commit
        case forcePushed
        /// `detail` carries the requested reviewer's login or team name.
        case reviewRequested
        case reviewRequestRemoved
    }

    let kind: Kind
    let actorLogin: String
    let actorAvatarURL: URL?
    let createdAt: Date?
    /// Kind-specific payload: the commit summary or the requested reviewer.
    var detail: String?
}

struct PullRequestDetail: Equatable, Sendable {
    let id: PullRequestIdentifier
    let title: String
    let url: URL?
    let status: PullRequestStatus
    let authorLogin: String
    let authorAvatarURL: URL?
    let headRefName: String
    let baseRefName: String
    let createdAt: Date?
    let updatedAt: Date?
    let additions: Int
    let deletions: Int
    let changedFiles: Int
    let bodyMarkdown: String
    let reviewDecision: String?
    let checks: [PullRequestCheck]
    var comments: [PullRequestComment]
    var reviews: [PullRequestReview]
    var reviewThreads: [PullRequestReviewThread]
    // `var`s with defaults so the memberwise init keeps existing call sites valid.
    var timelineEvents: [PullRequestTimelineEvent] = []
    /// Current review requests plus each past reviewer's latest verdict.
    var reviewers: [PullRequestReviewer] = []
    /// The pull request's own node id and reactions — the PR body is reactable too.
    var nodeID: String?
    var reactions: [PullRequestCommentReaction] = []
    /// The signed-in user, for attributing local pending comments before submission.
    var viewerLogin: String?
    var viewerAvatarURL: URL?
}

enum PullRequestReviewEvent: String, Sendable, Equatable {
    case approve = "APPROVE"
    case requestChanges = "REQUEST_CHANGES"
    case comment = "COMMENT"
}

struct PendingReviewSubmission: Equatable, Sendable {
    struct InlineComment: Equatable, Sendable {
        let path: String
        let line: Int
        let side: PullRequestDiffSide
        let body: String
    }

    let event: PullRequestReviewEvent
    let body: String
    let comments: [InlineComment]
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
    /// Submits a complete review — approval state plus any batched inline comments — in one call.
    func submitReview(_ id: PullRequestIdentifier, submission: PendingReviewSubmission) async throws
    /// Rewrites the body of an already-submitted review comment the viewer may update.
    func updateReviewComment(_ id: PullRequestIdentifier, commentID: Int, body: String) async throws
    /// Permanently deletes an already-submitted review comment the viewer may delete.
    func deleteReviewComment(_ id: PullRequestIdentifier, commentID: Int) async throws
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
}

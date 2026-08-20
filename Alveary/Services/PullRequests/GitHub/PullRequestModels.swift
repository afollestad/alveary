import Foundation

// The models a fetched pull request detail is made of: checks, comments,
// reviews, review threads, reviewers, and timeline events. The service
// protocol and its list-side models live in `PullRequestsService.swift`;
// local optimistic mutations of these live in `PullRequestModels+Optimistic.swift`.

struct PullRequestCheck: Equatable, Sendable, Identifiable {
    /// The check run's job name, or the legacy commit status's context.
    let name: String
    /// Workflow that produced the run, falling back to the posting app when a check run has no
    /// workflow run. Nil for legacy commit statuses, which belong to no workflow.
    ///
    /// A `var` with a default, matching `PullRequestDetail` below: a `let` with a default is
    /// dropped from the memberwise init entirely, which would pin this to nil forever.
    var workflowName: String?
    let state: PullRequestChecksState
    let detailsURL: URL?

    /// Unique because `makeChecks` collapses the rollup on exactly this pair, so two rows can
    /// never share one. Keyed on the pair rather than the check run's id because a legacy
    /// commit status has no id to key on.
    var id: String { "\(workflowName ?? "")\u{0}\(name)" }

    /// How github.com labels the row: `Workflow / Job`, or the bare name when there is no
    /// workflow. Two workflows may each define a job called `Release`, and the prefix is the
    /// only thing that tells those rows apart.
    var displayName: String {
        guard let workflowName, !workflowName.isEmpty else {
            return name
        }
        return "\(workflowName) / \(name)"
    }
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
    /// GraphQL `PullRequestReviewComment.state == PENDING`: written into the
    /// viewer's draft review but not yet sent with "Submit review...". GitHub
    /// shows these only to their author, and only the viewer can ever have one.
    let isPending: Bool
    /// Position in a review proposal's stored `comments` array, for a comment staged
    /// in Alveary and existing nowhere on GitHub — narrower than `isPending`, which
    /// means written into the viewer's server-side draft. The array position is the
    /// only identity a staged comment has, so it is what a Remove addresses; mirrors
    /// `DiffLineComment.proposedIndex`, which carries it on the Changes tab.
    let proposedIndex: Int?

    var isProposed: Bool {
        proposedIndex != nil
    }

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
        isBot: Bool = false,
        isPending: Bool = false,
        proposedIndex: Int? = nil
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
        self.isPending = isPending
        self.proposedIndex = proposedIndex
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
    /// `var` so optimistic remote edits can rewrite it locally.
    var bodyMarkdown: String
    let submittedAt: Date?
    /// REST id; needed to edit the review's summary body.
    let databaseId: Int?
    /// GraphQL node id; reviews take reactions like comments do.
    let nodeID: String?
    /// Permission-based, like comments. Submitted reviews have no delete
    /// counterpart — GitHub only deletes *pending* reviews.
    let viewerCanUpdate: Bool
    var reactions: [PullRequestCommentReaction]
    let isBot: Bool

    init(
        authorLogin: String,
        authorAvatarURL: URL?,
        state: PullRequestReviewState,
        bodyMarkdown: String,
        submittedAt: Date?,
        databaseId: Int? = nil,
        nodeID: String? = nil,
        viewerCanUpdate: Bool = false,
        reactions: [PullRequestCommentReaction] = [],
        isBot: Bool = false
    ) {
        self.authorLogin = authorLogin
        self.authorAvatarURL = authorAvatarURL
        self.state = state
        self.bodyMarkdown = bodyMarkdown
        self.submittedAt = submittedAt
        self.databaseId = databaseId
        self.nodeID = nodeID
        self.viewerCanUpdate = viewerCanUpdate
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
    /// Node id of the review the root comment was submitted with; the Overview
    /// timeline nests the thread under that review's card.
    let reviewNodeID: String?
    /// GitHub's own count, when the fetch reported one. `comments` is a page — a large one,
    /// but a page — so this is what may exceed it; nil means the array is the whole thread.
    let totalCommentCount: Int?

    /// How many comments the thread really has, which is not always how many were fetched.
    var commentCount: Int {
        max(totalCommentCount ?? comments.count, comments.count)
    }

    /// True when the fetch returned fewer comments than the thread holds, so a reader is
    /// looking at a prefix rather than the conversation.
    var hasUnfetchedComments: Bool {
        commentCount > comments.count
    }

    /// A thread the viewer has drafted but not submitted. GitHub creates the
    /// whole thread pending, so its root comment's state decides.
    var isPending: Bool {
        comments.first?.isPending == true
    }

    /// A thread synthesized from a review proposal's staged comments — Alveary-local,
    /// existing nowhere on GitHub until the review is submitted. Decided by the root
    /// comment like `isPending`, and mutually exclusive with it.
    var isProposed: Bool {
        comments.first?.isProposed == true
    }

    /// The REST id replies attach to — GitHub replies always target the root
    /// comment. Mirrors `DiffLineCommentThread.replyTargetCommentID`. Pending
    /// comments are skipped: GitHub accepts no reply until the review is submitted.
    var replyTargetCommentID: Int? {
        comments.first { $0.databaseId != nil && !$0.isPending }?.databaseId
    }

    init(
        path: String,
        line: Int?,
        side: PullRequestDiffSide,
        isResolved: Bool,
        isOutdated: Bool,
        comments: [PullRequestComment],
        diffHunkExcerpt: String? = nil,
        nodeID: String? = nil,
        reviewNodeID: String? = nil,
        totalCommentCount: Int? = nil
    ) {
        self.path = path
        self.line = line
        self.side = side
        self.isResolved = isResolved
        self.isOutdated = isOutdated
        self.comments = comments
        self.diffHunkExcerpt = diffHunkExcerpt
        self.nodeID = nodeID
        self.reviewNodeID = reviewNodeID
        self.totalCommentCount = totalCommentCount
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
    /// Mutable so an inline description edit can apply optimistically, like
    /// comment and review bodies do.
    var bodyMarkdown: String
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
    /// GitHub's own permission for editing the pull request body; gates the
    /// Overview description's inline editor, like comment menus gate on theirs.
    var viewerCanUpdate = false
    /// Whether the head branch still exists on GitHub (GraphQL `headRef` is null
    /// once it is deleted). Reopening a closed pull request without its branch
    /// fails with HTTP 422, so the footer's Reopen action gates on this.
    var headRefExists = true
    /// The viewer's own unsubmitted review, if one exists. `var` so creating one
    /// can apply optimistically; every pending-comment mutation is addressed
    /// through it, and submitting finishes *this* review rather than opening a
    /// second one beside it.
    var pendingReviewNodeID: String?
    /// The head commit the diff ends at. Image rows in the Changes tab fetch ordinary blob bytes by
    /// commit, so an image is left as a callout when this is missing.
    var headRefOid: String?
    /// The commit the diff starts from — GitHub's merge base for the comparison, which is what makes
    /// the "before" side of a modified image the version the diff actually shows.
    var baseRefOid: String?

    /// Threads holding the viewer's unsubmitted comments.
    var pendingReviewThreads: [PullRequestReviewThread] {
        reviewThreads.filter(\.isPending)
    }

    /// Drives the footer's "N pending comments" note and `.comment` submission
    /// validation, which used to read a local batch.
    var pendingCommentCount: Int {
        reviewThreads.reduce(0) { $0 + $1.comments.filter(\.isPending).count }
    }
}

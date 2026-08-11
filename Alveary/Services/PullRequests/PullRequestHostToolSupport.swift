import AgentCLIKit
import Foundation

/// The list scope `list_involved_prs` takes. Each narrow scope is one of the Pull Requests
/// screen's *sections* rather than one of its tabs: the screen's Reviewing tab renders both review
/// buckets and sections them, which a flat tool result cannot do, so `reviewing` here is the
/// "Pending review" half alone and `reviewed` is "Previously reviewed".
enum PullRequestHostToolListFilter: String, CaseIterable {
    case all
    case authored
    case reviewing
    case reviewed

    /// The involvement buckets this scope needs fetched, so every narrow filter costs one search
    /// instead of three.
    var requiredBuckets: Set<PullRequestInvolvementBucket> {
        switch self {
        case .all:
            return Set(PullRequestInvolvementBucket.allCases)
        case .authored:
            return [.authored]
        case .reviewing:
            return [.reviewRequested]
        case .reviewed:
            return [.reviewed]
        }
    }

    /// A re-requested pull request satisfies both review scopes: GitHub clears the review request
    /// when a review is submitted, so one carrying both flags was requested *again* afterwards and
    /// is genuinely waiting — matching the screen, where a re-request counts as pending.
    func matches(_ summary: PullRequestSummary) -> Bool {
        switch self {
        case .all:
            true
        case .authored:
            summary.isAuthored
        case .reviewing:
            summary.isReviewRequested
        case .reviewed:
            summary.hasReviewed
        }
    }
}

/// A `get_pr_timeline` request: one pull request plus how many newest entries to return.
struct PullRequestHostToolTimelineRequest {
    let identifier: PullRequestIdentifier
    let limit: Int
}

/// A `get_pr_diff` request. `paths` narrows to named files; `offset` is the
/// file index patch paging starts at, after any path filtering.
struct PullRequestHostToolDiffRequest {
    let identifier: PullRequestIdentifier
    let paths: [String]?
    let offset: Int
}

/// One inline comment in a `propose_pr_review` request.
struct PullRequestHostToolReviewCommentItem: Equatable {
    let path: String
    let line: Int
    let side: PullRequestDiffSide
    let body: String
}

/// A `reply_to_pr_thread` request.
struct PullRequestHostToolThreadReplyRequest {
    let identifier: PullRequestIdentifier
    let threadID: String
    let body: String
    let canonicalPayloadHash: String
}

/// A `resolve_pr_thread` / `unresolve_pr_thread` request. No hash: resolution is
/// idempotent, so a replay is harmless and keeps no receipt.
struct PullRequestHostToolResolutionRequest {
    let identifier: PullRequestIdentifier
    let threadID: String
}

/// What one mutating call needs to look up or write its receipt, derived once so the
/// handlers do not thread three values through every helper.
struct PullRequestHostToolCallIdentity {
    let deduplicationKey: String
    let processToken: UUID
    let requestDate: Date
}

/// The feature-specific handle a replayed receipt echoes back.
enum PullRequestHostToolReceiptHandle {
    case none
    /// A created review thread's GraphQL node id.
    case thread(String?)
    case proposal(String)
}

/// A `comment_on_pr` request.
struct PullRequestHostToolCommentRequest {
    let identifier: PullRequestIdentifier
    let body: String
    let canonicalPayloadHash: String
}

/// A `propose_pr_review` request. The event is already the wire enum — no host
/// state is needed to map it — but nothing is validated against GitHub yet. The
/// comments are ordered: they are staged and later written one at a time, so the
/// same set in a different order is a different call.
struct PullRequestHostToolReviewProposalRequest {
    let identifier: PullRequestIdentifier
    let event: PullRequestReviewEvent
    let body: String?
    let comments: [PullRequestHostToolReviewCommentItem]
    let canonicalPayloadHash: String
}

/// One date rendering for every pull-request-tool timestamp, matching the
/// catalog's `dateTimeSchema`.
enum PullRequestHostToolDates {
    static func canonical(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

/// Output bounds. AgentCLIKit replaces an oversized result with an error rather
/// than truncating it, and every payload is emitted twice (text fallback plus
/// structured content), so each cap has to leave half the wire budget free.
enum PullRequestHostToolLimits {
    /// `list_involved_prs` rows per call: both the default `limit` and its ceiling, and the page
    /// size each involvement bucket is fetched at — so a three-bucket call merges at most 150 rows
    /// down to this many.
    static let maxListRows = 50
    static let defaultTimelineLimit = 30
    static let maxTimelineLimit = 100
    /// Comment and review bodies inside list-shaped output.
    static let maxBodyCharacters = 2_000
    /// Comments one review thread's rendering may carry.
    static let maxThreadComments = 10
    /// Thread comments one response targets across *all* its threads. The per-thread cap alone
    /// is not a bound: `get_pr_timeline` can window 100 threads, so ten comments each would
    /// multiply into megabytes, and AgentCLIKit replaces an oversized result with an error
    /// rather than truncating it — the whole call would fail. Threads share this evenly.
    ///
    /// It is a target rather than a ceiling: `minThreadComments` outranks it, so a response with
    /// more than half this many threads exceeds it. That is deliberate — the real ceiling is
    /// `max(this, 2 × threadCount)`, and the fetch already caps threads at 100, so the worst case
    /// is 200 comments. Every thread keeping both ends is worth more than a round number.
    static let maxResponseThreadComments = 150
    /// The root is the feedback and the newest reply is where the thread stands, so no thread
    /// renders less than both — a thread showing only its root cannot say whether it was already
    /// answered, which is the question an address-feedback run is asking.
    static let minThreadComments = 2
    /// The pull request's own description in `get_pr`.
    static let maxDescriptionCharacters = 4_000
    /// Total patch text `get_pr_diff` includes before paging the rest.
    static let maxPatchBytes = 150 * 1024
    /// Comments one `propose_pr_review` call may carry. A proposal is the whole review — a
    /// second call supersedes the first, so this is a per-review ceiling, bounded by what the
    /// stored envelope and the confirmation card can reasonably hold.
    static let maxReviewCommentsPerProposal = 50
}

/// Shared JSON row builders, so `get_pr`, `get_pr_timeline`, and `get_pr_diff`
/// render authors and reactions identically.
enum PullRequestHostToolJSON {
    static func author(login: String, avatarURL: URL?) -> AgentCLIKit.JSONValue {
        var fields: [String: AgentCLIKit.JSONValue] = ["login": .string(login)]
        if let avatarURL {
            fields["avatar_url"] = .string(avatarURL.absoluteString)
        }
        return .object(fields)
    }

    static func reactions(_ reactions: [PullRequestCommentReaction]) -> AgentCLIKit.JSONValue {
        .array(reactions.map { reaction in
            .object([
                "emoji": .string(reaction.content.emoji),
                "count": .number(Double(reaction.count)),
                "viewer_reacted": .bool(reaction.viewerHasReacted)
            ])
        })
    }

    /// One review-thread comment, shared by `get_pr_timeline` and `get_pr_diff` so a thread
    /// reads the same whichever tool returned it.
    static func comment(_ comment: PullRequestComment) -> AgentCLIKit.JSONValue {
        let body = truncated(comment.bodyMarkdown, limit: PullRequestHostToolLimits.maxBodyCharacters)
        var row: [String: AgentCLIKit.JSONValue] = [
            "author": author(login: comment.authorLogin, avatarURL: comment.authorAvatarURL),
            "body_markdown": .string(body.text),
            "body_truncated": .bool(body.wasTruncated),
            "is_bot": .bool(comment.isBot),
            "is_pending": .bool(comment.isPending)
        ]
        if let createdAt = comment.createdAt {
            row["created_at"] = .string(PullRequestHostToolDates.canonical(createdAt))
        }
        if !comment.reactions.isEmpty {
            row["reactions"] = reactions(comment.reactions)
        }
        return .object(row)
    }

    /// How many comments each thread may render when a response carries `threadCount` of them.
    /// Every thread keeps at least its root and the newest reply — the feedback and where it
    /// stands — so a response with many threads goes shallow rather than dropping threads.
    static func threadCommentAllowance(threadCount: Int) -> Int {
        guard threadCount > 1 else {
            return PullRequestHostToolLimits.maxThreadComments
        }
        let share = PullRequestHostToolLimits.maxResponseThreadComments / threadCount
        return min(
            PullRequestHostToolLimits.maxThreadComments,
            max(PullRequestHostToolLimits.minThreadComments, share)
        )
    }

    /// Bounds one thread's comments. The root comment is the feedback itself and the tail is
    /// where the thread currently stands — including whether the user already replied — so a
    /// long thread keeps both ends and drops the middle rather than its most recent turns.
    ///
    /// `wasTruncated` also covers comments the *fetch* never returned, so a caller reporting it
    /// is telling the truth about the whole pipeline rather than only about this cap.
    static func boundedThreadComments(
        _ thread: PullRequestReviewThread,
        limit: Int = PullRequestHostToolLimits.maxThreadComments
    ) -> (comments: [PullRequestComment], wasTruncated: Bool) {
        let comments = thread.comments
        guard comments.count > limit, let root = comments.first else {
            return (comments, thread.hasUnfetchedComments)
        }
        return ([root] + comments.suffix(limit - 1), true)
    }

    /// Bounds a markdown body for list-shaped output. The flag rides beside the
    /// text so the model knows the tail exists rather than assuming it read it.
    static func truncated(_ text: String, limit: Int) -> (text: String, wasTruncated: Bool) {
        guard text.count > limit else {
            return (text, false)
        }
        return (String(text.prefix(limit)) + "…", true)
    }
}

/// Shared text-fallback rows. Codex surfaces only the text half of a result, so a thread has
/// to read as well there as it does in `structuredContent`.
enum PullRequestHostToolText {
    /// One line per comment, bounded exactly as the structured half is, with a note wherever
    /// comments are missing so the text reader is not left thinking it saw the whole
    /// conversation. The two gaps sit at opposite ends and say opposite things: the render cap
    /// drops the *middle*, while the fetch page drops the *newest* replies — and a note calling
    /// the latter "earlier" would tell the model it has the thread's last word when it does not.
    static func threadCommentLines(
        _ thread: PullRequestReviewThread,
        indent: String,
        limit: Int = PullRequestHostToolLimits.maxThreadComments
    ) -> [String] {
        let bounded = PullRequestHostToolJSON.boundedThreadComments(thread, limit: limit)
        var lines = bounded.comments.map { comment in
            let body = PullRequestHostToolJSON.truncated(
                comment.bodyMarkdown,
                limit: PullRequestHostToolLimits.maxBodyCharacters
            )
            return "\(indent)\(comment.authorLogin): \(body.text.replacingOccurrences(of: "\n", with: " "))"
        }
        let capOmitted = thread.comments.count - bounded.comments.count
        if capOmitted > 0, !lines.isEmpty {
            lines.insert("\(indent)(\(capOmitted) earlier \(replyNoun(capOmitted)) omitted)", at: 1)
        }
        let unfetched = thread.commentCount - thread.comments.count
        if unfetched > 0 {
            lines.append("\(indent)(\(unfetched) newer \(replyNoun(unfetched)) not fetched)")
        }
        return lines
    }

    private static func replyNoun(_ count: Int) -> String {
        count == 1 ? "reply" : "replies"
    }
}

enum PullRequestHostToolServiceError: LocalizedError, Equatable {
    case unsupportedTool
    case missingRequestIdentity
    case sourceConversationUnavailable
    case sourceProviderMismatch
    case automatedRunCannotClosePullRequest
    case pullRequestsDisabled
    case invalidPullRequestURL(String)
    case pullRequestUnavailable(String)
    case reviewThreadNotFound(threadID: String)
    case reviewThreadPendingNoReplies
    case reviewThreadMissingReplyTarget
    case reviewThreadMissingResolutionHandle
    case reviewBodyRequired
    case reviewCommentRequired
    case reviewCommentAnchorInvalid(index: Int, path: String, line: Int, side: String)
    case cannotReviewOwnPullRequest
    case pullRequestNotReviewable(status: String)
    case stateChangeNotPermitted
    case cannotChangeMergedPullRequest
    case cannotReopenWithoutHeadBranch(branch: String)
    case cannotMarkClosedPullRequestReady(status: String)
    case cannotConvertPullRequestToDraft(status: String)
    case proposalPendingForDifferentPullRequest(displayKey: String)
    case diffOffsetOutOfRange(offset: Int, fileCount: Int)
    case diffPathsUnknown([String])
    case diffTooLarge
    case persistenceFailure

    var errorDescription: String? {
        switch self {
        case .unsupportedTool:
            "This Alveary host tool is not available."
        case .missingRequestIdentity:
            "Alveary could not verify this pull request request for safe retry handling."
        case .sourceConversationUnavailable:
            "Alveary pull request tools require an active, saved Project or Task conversation."
        case .sourceProviderMismatch:
            "The pull request request provider does not match its source conversation."
        case .automatedRunCannotClosePullRequest:
            "Automated scheduled runs cannot close pull requests. Leave it open and tell the user " +
                "why it should be closed."
        case .pullRequestsDisabled:
            "Pull request integration is turned off in Alveary's settings. Ask the user to enable " +
                "Pull Requests in Alveary's Git settings if they want these tools."
        case .invalidPullRequestURL(let url):
            "\(url) is not a GitHub pull request. Pass a URL like https://github.com/owner/repo/pull/123, " +
                "or the owner/repo#123 shorthand."
        case .pullRequestUnavailable(let reason):
            "Alveary could not reach that pull request on GitHub: \(reason)"
        case .reviewThreadNotFound(let threadID):
            "No review thread with the ID \(threadID) exists on that pull request. Call get_pr_diff or " +
                "get_pr_timeline and use one of the thread_id values they return."
        case .reviewThreadPendingNoReplies:
            "That review thread is part of the user's unsubmitted pending review, and GitHub accepts no " +
                "replies until the review is submitted. Include a comment on that line in a propose_pr_review " +
                "call instead."
        case .reviewThreadMissingReplyTarget:
            "That review thread has no comment GitHub will accept a reply to. Call get_pr_diff " +
                "again for its current state."
        case .reviewThreadMissingResolutionHandle:
            "That review thread cannot be resolved or unresolved from here. Call get_pr_diff again for a " +
                "fresh thread_id."
        case .reviewBodyRequired:
            "Requesting changes requires a body summarizing what should change. Call propose_pr_review " +
                "again with one."
        case .reviewCommentRequired:
            "A comment review needs a body, at least one comment in this call, or at least one " +
                "pending review comment. Pass comments or a body."
        case let .reviewCommentAnchorInvalid(index, path, line, side):
            "comments[\(index)] does not land on a line in the diff: \(path):\(line) (\(side)). " +
                "Anchor every comment to a path, line, and side reported by get_pr_diff."
        case .cannotReviewOwnPullRequest:
            "GitHub does not accept approving or requesting changes on the user's own pull request. " +
                "Propose a comment review instead."
        case .pullRequestNotReviewable(let status):
            "That pull request is \(status), so a review can no longer be submitted on it."
        case .stateChangeNotPermitted:
            "The user does not have write access to that pull request, so its state cannot be " +
                "changed from here."
        case .cannotChangeMergedPullRequest:
            "That pull request is merged. GitHub allows no state changes on a merged pull request."
        case .cannotReopenWithoutHeadBranch(let branch):
            "That pull request cannot be reopened because its branch \(branch) no longer exists " +
                "on GitHub."
        case .cannotMarkClosedPullRequestReady(let status):
            "That pull request is \(status), so it cannot be marked ready for review. Only an " +
                "open draft can."
        case .cannotConvertPullRequestToDraft(let status):
            "That pull request is \(status), so it cannot be returned to draft. Only an open pull " +
                "request can."
        case .proposalPendingForDifferentPullRequest(let displayKey):
            "A review proposal for \(displayKey) is already awaiting the user's confirmation in this " +
                "conversation. Ask the user to confirm or reject it before proposing another."
        case let .diffOffsetOutOfRange(offset, fileCount):
            "offset \(offset) is past the end of the diff, which has \(fileCount) file(s). Valid offsets " +
                "are 0 through \(max(0, fileCount - 1))."
        case .diffPathsUnknown(let paths):
            "The diff contains no file(s) named: \(paths.joined(separator: ", ")). Call get_pr_diff " +
                "without paths to see the file list."
        case .diffTooLarge:
            "That pull request's diff is too large for Alveary to fetch. Review it on GitHub instead."
        case .persistenceFailure:
            "Alveary could not read or save pull request tool state."
        }
    }
}

import AgentCLIKit
import Foundation

/// The list scope `list_involved_prs` takes; the mapping to summary flags matches the
/// Pull Requests screen's tabs so the tool and the UI never disagree.
enum PullRequestHostToolListFilter: String, CaseIterable {
    case all
    case authored
    case reviewing

    func matches(_ summary: PullRequestSummary) -> Bool {
        switch self {
        case .all:
            true
        case .authored:
            summary.isAuthored
        case .reviewing:
            summary.isReviewRequested || summary.hasReviewed
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

/// One comment in an `add_pr_review_comments` request.
struct PullRequestHostToolReviewCommentItem {
    let path: String
    let line: Int
    let side: PullRequestDiffSide
    let body: String
}

/// An `add_pr_review_comments` request, paired with the hash that identifies an
/// exact retry of it. The comments are ordered: they are written one at a time, so
/// the same set in a different order is a different call.
struct PullRequestHostToolReviewCommentsRequest {
    let identifier: PullRequestIdentifier
    let comments: [PullRequestHostToolReviewCommentItem]
    let canonicalPayloadHash: String
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
    /// One outcome per comment an `add_pr_review_comments` call was given, in the
    /// order they were requested, so a replay reproduces the per-item rows.
    case commentBatch([PullRequestHostToolReceiptCommentOutcome])
    case proposal(String)
}

/// A `comment_on_pr` request.
struct PullRequestHostToolCommentRequest {
    let identifier: PullRequestIdentifier
    let body: String
    let canonicalPayloadHash: String
}

/// A `propose_pr_review` request. The event is already the wire enum — no host
/// state is needed to map it — but nothing is validated against GitHub yet.
struct PullRequestHostToolReviewProposalRequest {
    let identifier: PullRequestIdentifier
    let event: PullRequestReviewEvent
    let body: String?
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
    /// `list_involved_prs` rows; the merged fetch caps at 150 (50 per involvement bucket).
    static let maxListRows = 50
    static let defaultTimelineLimit = 30
    static let maxTimelineLimit = 100
    /// Comment and review bodies inside list-shaped output.
    static let maxBodyCharacters = 2_000
    /// The pull request's own description in `get_pr`.
    static let maxDescriptionCharacters = 4_000
    /// Total patch text `get_pr_diff` includes before paging the rest.
    static let maxPatchBytes = 150 * 1024
    /// Comments one `add_pr_review_comments` call may carry. Each is a separate GitHub
    /// round trip and an output row, and the model can call again for the rest.
    static let maxReviewCommentsPerCall = 20
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

    /// Bounds a markdown body for list-shaped output. The flag rides beside the
    /// text so the model knows the tail exists rather than assuming it read it.
    static func truncated(_ text: String, limit: Int) -> (text: String, wasTruncated: Bool) {
        guard text.count > limit else {
            return (text, false)
        }
        return (String(text.prefix(limit)) + "…", true)
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
                "replies until the review is submitted. Add a separate comment with add_pr_review_comments instead."
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
            "A comment review needs a body or at least one pending review comment. Add one with " +
                "add_pr_review_comments, or pass a body."
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

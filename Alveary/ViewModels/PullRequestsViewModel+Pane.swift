import Foundation
import SwiftData

enum PullRequestPaneTarget: Hashable {
    case details(PullRequestIdentifier)

    var identifier: PullRequestIdentifier {
        switch self {
        case .details(let id):
            return id
        }
    }
}

/// Which surface opened the active pane. The pane lane is shared, so the root
/// only renders a target whose origin matches the current selection — otherwise
/// a pull request opened from the Pull Requests screen would follow the user
/// onto an unrelated thread, and vice versa.
enum PullRequestPaneOrigin: Hashable {
    case screen
    case thread(PersistentIdentifier)
    case project(PersistentIdentifier)

    /// A link's owner is also the surface its pane opens from.
    init(owner: PullRequestLinkOwner) {
        switch owner {
        case .thread(let id):
            self = .thread(id)
        case .project(let id):
            self = .project(id)
        }
    }
}

enum PullRequestDiffState: Equatable {
    case loading
    case loaded
    case tooLarge
    case failed(String)
}

/// One in-flight pane load. The `token` is what completion cleanup matches on: a
/// restart reuses the session's generation, so nothing else distinguishes a
/// cancelled load from the one that replaced it.
struct PullRequestPaneLoad {
    let token: UUID
    let task: Task<Void, Never>
}

/// The in-flight detail and diff loads for one pane target. Cancellation is the
/// concurrency bound for pane fetches — only the pane the user is looking at keeps
/// loads running — so these handles have to be reachable, not discarded at spawn.
struct PullRequestPaneLoadTasks {
    var detail: PullRequestPaneLoad?
    var diff: PullRequestPaneLoad?

    var isEmpty: Bool {
        detail == nil && diff == nil
    }

    func cancelAll() {
        detail?.task.cancel()
        diff?.task.cancel()
    }
}

struct PullRequestPaneSession: Equatable {
    let generation: UUID
    /// The list row that opened the pane; keeps the header and overview populated
    /// while the full detail fetch is in flight. Nil when the pane was opened from
    /// an identifier alone — a transcript unlink card names a pull request no
    /// stored snapshot covers — until `loadDetail` backfills it.
    var summary: PullRequestSummary?
    var detail: PullRequestDetail?
    var detailError: String?
    var isLoadingDetail = true
    var diffFiles: [DiffFile]?
    var diffState = PullRequestDiffState.loading
    var renderedDiffFileCount = PullRequestDiffFilePaging.initialFileCount
    var collapsedDiffFileIDs: Set<String> = []
    var pendingReview = PendingReviewDraft()
    var composerAnchor: DiffCommentAnchor?
    var composerText = ""
    /// Set while the composer is rewriting an already-submitted review-thread comment.
    var composerRemoteCommentID: Int?
    /// Set while the composer is rewriting an unsubmitted (pending) review comment.
    /// Separate from `composerRemoteCommentID` because pending comments are edited
    /// through GraphQL by node id, not `PATCH pulls/comments/{id}`.
    var composerPendingCommentNodeID: String?
    /// Set while the composer is rewriting an already-submitted top-level
    /// conversation comment (an issue comment, in GitHub terms).
    var composerIssueCommentID: Int?
    /// Set while the composer is rewriting an already-submitted review's summary body.
    var composerReviewID: Int?
    /// Set while the composer is replying to an existing thread; holds the REST id
    /// of the thread's root comment.
    var composerReplyToCommentID: Int?
    /// Set while the Overview's description is being edited inline. The pull
    /// request needs no id here — the pane's target identifies it.
    var isEditingDescription = false
    var composerError: String?
    /// Re-request failures render beside the Overview's Reviewers section — the
    /// screen the action lives on — not the Files-tab comment banner.
    var reviewersError: String?
    /// Logins with a re-request round trip running; their buttons disable so the
    /// action cannot double-fire before the refetch flips the row to "requested".
    var reRequestsInFlight: Set<String> = []
    /// Set while a close or reopen round trip runs; disables the footer's action.
    var isChangingState = false
    /// A failed close or reopen; rendered as a banner in the review footer, where
    /// the action lives.
    var stateChangeError: String?
    /// Set while the agentic review's thread is being created; disables the footer's
    /// split button so the action cannot double-fire into two review threads.
    var isStartingAgenticReview = false
    /// A failed agentic review start; rendered beside `stateChangeError` in the footer.
    var agenticReviewError: String?
    /// Non-nil token asks the freshly mounted composer editor to take first responder.
    var composerFocusToken: UUID?
    /// Awaiting user confirmation before permanently deleting a submitted comment.
    var pendingRemoteCommentDeletion: PendingRemoteCommentDeletion?
    /// A one-shot ask to scroll the Changes tab to an anchor, cleared once the scroll fires.
    ///
    /// The pane holds no proposal state beside this: which staged comments it renders follows from
    /// the pull request, not from how the pane was opened (see `pendingReviewProposal(for:)`).
    var pendingCommentScrollTarget: PullRequestPaneCommentScrollTarget?
}

/// A pending scroll to one diff comment. The token is what consumption matches on — clearing
/// blind would let a stale consumer swallow a newer request — mirroring
/// `NotificationRouter.clearPendingIfMatches` and `AppState.clearPendingSettingsTargetPage`.
struct PullRequestPaneCommentScrollTarget: Equatable {
    let token: UUID
    let anchor: DiffCommentAnchor

    /// The `FlattenedDiffPreview` row id this resolves to.
    var rowID: String {
        "comment:\(anchor.key)"
    }
}

struct PendingRemoteCommentDeletion: Equatable, Sendable {
    /// Which REST endpoint the confirmed deletion targets.
    enum Kind: Equatable, Sendable {
        /// A review-thread comment — `pulls/comments/{id}`.
        case reviewComment
        /// A top-level conversation comment — `issues/comments/{id}`.
        case issueComment
    }

    let kind: Kind
    let remoteID: Int
}

/// The local half of a review in progress: the overall summary plus submission
/// state. Inline comments are *not* here — they post to GitHub as pending review
/// comments the moment they are saved, so they survive quitting the app and show
/// up on github.com. The summary stays local, matching github.com, whose
/// "Finish your review" box is likewise not persisted until submit.
struct PendingReviewDraft: Equatable, Sendable {
    var overallComment = ""
    var isSubmitting = false
    var submissionError: String?
}

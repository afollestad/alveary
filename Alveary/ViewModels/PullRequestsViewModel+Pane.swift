import Foundation

enum PullRequestPaneTarget: Hashable {
    case details(PullRequestIdentifier)

    var identifier: PullRequestIdentifier {
        switch self {
        case .details(let id):
            return id
        }
    }
}

enum PullRequestDiffState: Equatable {
    case loading
    case loaded
    case tooLarge
    case failed(String)
}

struct PullRequestPaneSession: Equatable {
    let generation: UUID
    /// The list row that opened the pane; keeps the header and overview populated
    /// while the full detail fetch is in flight.
    var summary: PullRequestSummary
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
    /// Set while the composer is rewriting an already-submitted comment.
    var composerRemoteCommentID: Int?
    /// Set while the composer is replying to an existing thread; holds the REST id
    /// of the thread's root comment.
    var composerReplyToCommentID: Int?
    var composerError: String?
    /// Re-request failures render beside the Overview's Reviewers section — the
    /// screen the action lives on — not the Files-tab comment banner.
    var reviewersError: String?
    /// Logins with a re-request round trip running; their buttons disable so the
    /// action cannot double-fire before the refetch flips the row to "requested".
    var reRequestsInFlight: Set<String> = []
    /// Non-nil token asks the freshly mounted composer editor to take first responder.
    var composerFocusToken: UUID?
    /// Awaiting user confirmation before permanently deleting a submitted comment.
    var pendingRemoteCommentDeletion: PendingRemoteCommentDeletion?
}

struct PendingRemoteCommentDeletion: Equatable, Sendable {
    let anchor: DiffCommentAnchor
    let remoteID: Int
    let bodyPreview: String
}

struct PendingReviewComment: Identifiable, Equatable, Sendable {
    let id: UUID
    let anchor: DiffCommentAnchor
    var body: String
}

/// The local pending review batch: inline comments plus the overall summary,
/// submitted together in one call. Intentionally in-memory only — closing the
/// pane keeps the cached session; quitting the app drops the draft.
struct PendingReviewDraft: Equatable, Sendable {
    var comments: [PendingReviewComment] = []
    var overallComment = ""
    var isSubmitting = false
    var submissionError: String?
}

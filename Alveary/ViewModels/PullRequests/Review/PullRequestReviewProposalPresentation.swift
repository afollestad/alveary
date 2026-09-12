import Foundation

/// What a review-proposal card renders and acts on, resolved from the stored envelope.
struct PullRequestReviewProposalPresentation: Identifiable, Equatable {
    let id: String
    let sourceConversationID: String
    let identifier: PullRequestIdentifier
    let title: String
    /// What the model asked for. The user may confirm a different verdict.
    let proposedEvent: PullRequestReviewEvent
    let body: String?
    /// The review's staged inline comments, held in the envelope until the user confirms.
    let comments: [PullRequestReviewProposalRecord.Comment]
    /// The user's own already-pending draft comments on GitHub, distinct from `comments`.
    let pendingCommentCount: Int
    /// Frozen reviewer labels for collective evidence; empty for host-tool proposals.
    let reviewers: [PullRequestReviewProposalRecord.Reviewer]
    /// Local completion context, never part of the review submitted to GitHub.
    let collectiveCompletionWarning: String?
    let createdAt: Date

    init(
        id: String,
        sourceConversationID: String,
        identifier: PullRequestIdentifier,
        title: String,
        proposedEvent: PullRequestReviewEvent,
        body: String?,
        comments: [PullRequestReviewProposalRecord.Comment],
        pendingCommentCount: Int,
        reviewers: [PullRequestReviewProposalRecord.Reviewer] = [],
        collectiveCompletionWarning: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.sourceConversationID = sourceConversationID
        self.identifier = identifier
        self.title = title
        self.proposedEvent = proposedEvent
        self.body = body
        self.comments = comments
        self.pendingCommentCount = pendingCommentCount
        self.reviewers = reviewers
        self.collectiveCompletionWarning = collectiveCompletionWarning
        self.createdAt = createdAt
    }

    var displayKey: String {
        identifier.displayKey
    }

    /// Sidecar metadata stays out of the GitHub comment models used by Overview and submission.
    var voteEvidenceByProposedIndex: [Int: PullRequestReviewVotePresentation] {
        Dictionary(uniqueKeysWithValues: comments.enumerated().compactMap { index, comment in
            comment.evidence.map { (index, PullRequestReviewVotePresentation(evidence: $0, reviewers: reviewers)) }
        })
    }
}

/// Confirm-time failures of the proposal flow itself, beside the service's own errors.
enum PullRequestReviewProposalSubmissionError: LocalizedError {
    case missingNodeID
    /// Comments whose lines the pull request's current diff cannot place. Refused before anything
    /// is created, so a stale anchor cannot strand a half-written draft on GitHub.
    case staleAnchors(paths: [String])

    var errorDescription: String? {
        switch self {
        case .missingNodeID:
            return "Alveary could not read the pull request's GitHub node ID to stage the review's comments. Try again."
        case .staleAnchors(let paths):
            let files = Set(paths).sorted().joined(separator: ", ")
            return """
                The pull request has changed since this review was written, and \(paths.count) \
                comment\(paths.count == 1 ? "" : "s") no longer \(paths.count == 1 ? "matches" : "match") \
                the diff (\(files)). Remove \(paths.count == 1 ? "it" : "them") from the card, or ask \
                for a fresh review.
                """
        }
    }
}

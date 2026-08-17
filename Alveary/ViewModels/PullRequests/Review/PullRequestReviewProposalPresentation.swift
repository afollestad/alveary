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
    let createdAt: Date

    var displayKey: String {
        identifier.displayKey
    }
}

/// Confirm-time failures of the proposal flow itself, beside the service's own errors.
enum PullRequestReviewProposalSubmissionError: LocalizedError {
    case missingNodeID

    var errorDescription: String? {
        "Alveary could not read the pull request's GitHub node ID to stage the review's comments. Try again."
    }
}

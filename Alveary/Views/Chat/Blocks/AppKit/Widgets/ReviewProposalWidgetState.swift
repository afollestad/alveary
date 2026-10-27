import Foundation

/// Everything a review-proposal card needs from `PullRequestReviewProposalCoordinator`, resolved
/// per render because confirmation state lives outside the harness turn.
struct ReviewProposalWidgetState: Equatable {
    /// A submitted card's comments and what it may do with them.
    struct Published: Equatable {
        let review: PullRequestPublishedReview
        /// False in a conversation that did not submit it, which renders the card read-only.
        let allowsActions: Bool
        var busyCommentIDs: Set<String> = []
        var errorMessage: String?
    }

    let presentation: PullRequestReviewProposalPresentation?
    let preview: PullRequestReviewProposalPreviewState?
    let selectedEvent: PullRequestReviewEvent?
    let canSubmit: Bool
    let isSubmitting: Bool
    let errorMessage: String?
    let published: Published?

    init(
        presentation: PullRequestReviewProposalPresentation? = nil,
        preview: PullRequestReviewProposalPreviewState? = nil,
        selectedEvent: PullRequestReviewEvent? = nil,
        canSubmit: Bool = false,
        isSubmitting: Bool = false,
        errorMessage: String? = nil,
        published: Published? = nil
    ) {
        self.presentation = presentation
        self.preview = preview
        self.selectedEvent = selectedEvent
        self.canSubmit = canSubmit
        self.isSubmitting = isSubmitting
        self.errorMessage = errorMessage
        self.published = published
    }
}

/// Use one body resolution for asynchronous preparation and the visible card. A live clear is authoritative.
extension ReviewProposalWidgetState {
    static func summaryBody(for entry: HostToolWidgetEntry, state: ReviewProposalWidgetState?) -> String? {
        guard case .pullRequestReviewProposal(let content) = entry.content, content.status != .failed else { return nil }
        if entry.outcome != nil { return entry.outcomeBody ?? content.body }
        if let presentation = state?.presentation { return presentation.body ?? "" }
        return content.body
    }
}

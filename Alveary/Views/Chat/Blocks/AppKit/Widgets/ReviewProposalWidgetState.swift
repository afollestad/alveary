import Foundation

/// Everything a review-proposal card needs from `PullRequestReviewProposalCoordinator`, resolved
/// per render because confirmation state lives outside the provider turn.
struct ReviewProposalWidgetState: Equatable {
    let presentation: PullRequestReviewProposalPresentation?
    let preview: PullRequestReviewProposalPreviewState?
    let selectedEvent: PullRequestReviewEvent?
    let canSubmit: Bool
    let isSubmitting: Bool
    let errorMessage: String?

    init(
        presentation: PullRequestReviewProposalPresentation? = nil,
        preview: PullRequestReviewProposalPreviewState? = nil,
        selectedEvent: PullRequestReviewEvent? = nil,
        canSubmit: Bool = false,
        isSubmitting: Bool = false,
        errorMessage: String? = nil
    ) {
        self.presentation = presentation
        self.preview = preview
        self.selectedEvent = selectedEvent
        self.canSubmit = canSubmit
        self.isSubmitting = isSubmitting
        self.errorMessage = errorMessage
    }
}

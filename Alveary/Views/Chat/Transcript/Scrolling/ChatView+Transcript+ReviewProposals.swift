import Foundation
import SwiftData

extension ChatTranscriptView {
    /// Wires the review-proposal card: the diff preview it renders, the verdict picker, and the
    /// confirm/reject decision that submits to GitHub.
    ///
    /// Unlike the scheduling proposal beside it, confirming here is asynchronous, so the card
    /// reads its in-flight state from the coordinator rather than a single `isResolving` flag.
    func configureAppKitReviewProposals(_ configuration: inout AppKitTranscriptRowFactory.Configuration) {
        // State resolves through closures, so a proposal notification re-renders by bumping this
        // revision rather than by changing any stored input.
        _ = reviewProposalRevision
        guard let coordinator = pullRequestReviewProposalCoordinator else {
            return
        }
        // Identity snapshots off the view model, never `viewModel.conversation`: this runs in
        // `ChatTranscriptView.body`, whose revision bumps can re-enter after a delete.
        let conversationID = viewModel.conversationID
        configuration.reviewProposalAvatarLoader = coordinator.avatarLoader
        configuration.reviewProposalState = { proposalID in
            Self.reviewProposalState(
                proposalID: proposalID,
                conversationID: conversationID,
                coordinator: coordinator
            )
        }
        configuration.conversationReviewProposal = {
            // A provider that emits only the text fallback gives the card no proposal id, and a
            // conversation holds one review proposal at a time.
            guard let proposalID = coordinator.presentations.values
                .first(where: { $0.sourceConversationID == conversationID })?.id else {
                return nil
            }
            return Self.reviewProposalState(
                proposalID: proposalID,
                conversationID: conversationID,
                coordinator: coordinator
            )
        }
        configuration.onSelectReviewVerdict = { proposalID, event in
            coordinator.selectEvent(event, forProposalID: proposalID)
        }
        configuration.onConfirmReviewProposal = { proposalID, event in
            Task { await coordinator.confirm(proposalID: proposalID, event: event) }
        }
        configuration.onRejectReviewProposal = { proposalID in
            coordinator.reject(proposalID: proposalID)
        }
        configuration.onRemoveReviewProposalComment = { proposalID, index in
            coordinator.removeStagedComment(proposalID: proposalID, at: index)
        }
        let threadID = viewModel.threadModelID
        configuration.onJumpToReviewProposalComment = { proposalID, anchor in
            Self.postJumpRequest(
                proposalID: proposalID,
                anchor: anchor,
                threadID: threadID,
                coordinator: coordinator
            )
        }
    }

    /// The transcript reaches neither the browsing view model nor the pane lane, so a jump travels
    /// as a notification the way the link cards' open does. It carries only the anchor: the pane
    /// resolves the pull request's pending proposal itself, so opening from here shows the same
    /// staged comments any other route would.
    private static func postJumpRequest(
        proposalID: String,
        anchor: DiffCommentAnchor,
        threadID: PersistentIdentifier?,
        coordinator: PullRequestReviewProposalCoordinator
    ) {
        guard let threadID,
              let identifier = coordinator.presentation(forProposalID: proposalID)?.identifier else {
            return
        }
        NotificationCenter.default.post(
            name: .pullRequestPaneRequested,
            object: nil,
            userInfo: [
                PullRequestPaneRequestNotificationKey.request: PullRequestPaneRequest(
                    identifier: identifier,
                    threadID: threadID,
                    commentAnchor: anchor
                )
            ]
        )
    }

    private static func reviewProposalState(
        proposalID: String,
        conversationID: String,
        coordinator: PullRequestReviewProposalCoordinator
    ) -> ReviewProposalWidgetState? {
        guard let presentation = coordinator.presentation(forProposalID: proposalID) else {
            return nil
        }
        // A forked or unrelated conversation renders the same widget read-only.
        guard presentation.sourceConversationID == conversationID else {
            return ReviewProposalWidgetState()
        }
        // Loading is lazy: a card only fetches its diff once it is actually on screen.
        coordinator.ensurePreview(proposalID: proposalID)
        let event = coordinator.selectedEvent(forProposalID: proposalID) ?? presentation.proposedEvent
        return ReviewProposalWidgetState(
            presentation: presentation,
            preview: coordinator.preview(forProposalID: proposalID),
            selectedEvent: event,
            canSubmit: coordinator.canSubmit(proposalID: proposalID, event: event),
            isSubmitting: coordinator.isSubmitting(proposalID: proposalID),
            errorMessage: coordinator.errorMessage(forProposalID: proposalID)
        )
    }
}

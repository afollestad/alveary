import AppKit

extension AppKitTranscriptRowFactory {
    func hostToolWidgetRow(
        id: String,
        entry: HostToolWidgetEntry,
        configuration: Configuration
    ) -> AppKitTranscriptLayoutRow {
        let view = cachedView(for: id, as: AppKitTranscriptHostToolWidgetRowView.self)
        view.onHeightInvalidated = heightInvalidationHandler(for: id, configuration: configuration)
        view.onImmediateHeightInvalidated = heightInvalidationHandler(for: id, animatesLayoutChanges: false, configuration: configuration)
        view.onConfirmScheduledProposal = configuration.onConfirmScheduledProposal
        view.onReviewScheduledProposal = configuration.onReviewScheduledProposal
        view.onRejectScheduledProposal = configuration.onRejectScheduledProposal
        view.onOpenScheduledTask = configuration.onOpenScheduledTask
        view.onOpenPullRequest = configuration.onOpenPullRequest
        view.onOpenThread = configuration.onOpenThread
        view.onConfirmReviewProposal = configuration.onConfirmReviewProposal
        view.onRejectReviewProposal = configuration.onRejectReviewProposal
        view.onSelectReviewVerdict = configuration.onSelectReviewVerdict
        view.onRemoveReviewProposalComment = configuration.onRemoveReviewProposalComment
        view.onUpdateReviewProposalBody = configuration.onUpdateReviewProposalBody
        view.onJumpToReviewProposalComment = configuration.onJumpToReviewProposalComment
        view.avatarLoader = configuration.reviewProposalAvatarLoader
        // Straight to the body, which the shell exposes: the shell has no use for these itself.
        view.reviewProposalBody.onEditPublishedComment = configuration.publishedReviewCommentActions.edit
        view.reviewProposalBody.onDeletePublishedComment = configuration.publishedReviewCommentActions.delete
        view.onOpenMarkdownLink = configuration.onOpenMarkdownLink
        // A resolved widget must not adopt the conversation's *next* proposal, so the
        // conversation-scoped fallback only applies while this one is still unresolved.
        let presentation = entry.scheduledProposalID.flatMap(configuration.scheduledProposalPresentation)
            ?? (entry.isUnresolvedProposal ? configuration.conversationScheduledProposal() : nil)
        // The list tool's live rows double as the run-state feed; they already sit in
        // the bridge's content signature, so tense flips re-render without new wiring.
        let targetRow = entry.resolvedScheduledTaskID.flatMap { taskID in
            configuration.scheduledTaskListActions.rows().first { $0.id == taskID }
        }
        // Same rule as the scheduling proposal above: a resolved card must not adopt the
        // conversation's next review proposal.
        let review = configuration.reviewState(for: entry)
        let summaryRequest = reviewSummaryPreparationRequest(id: id, entry: entry, state: review)
        view.configure(
            .init(
                entry: entry,
                proposalPresentation: presentation,
                reviewProposal: review,
                isProposalInteractive: presentation.map { configuration.isScheduledProposalInteractive($0.id) }
                    ?? (review?.presentation != nil),
                isResolving: configuration.isResolvingScheduledProposal,
                isTargetRunInFlight: targetRow?.hasActiveRun ?? false,
                errorMessage: configuration.scheduledProposalErrorMessage,
                bubbleMaxWidth: configuration.bubbleMaxWidth,
                typography: configuration.typography,
                reviewSummaryDocument: summaryRequest.flatMap { preparedMarkdownDocuments[$0] }
            )
        )
        return .init(id: id, view: view)
    }

    /// A collective run's status messages follow its card, so they stay above the proposal card it stages.
    func reviewTeamMessageRows(entry: HostToolWidgetEntry, configuration: Configuration) -> [AppKitTranscriptLayoutRow] {
        guard case .collectiveReviewRun(let run) = entry.content else { return [] }
        return ReviewTeamStatusMessage.messages(for: run).map { message in
            let view = cachedView(for: message.id, as: AppKitTranscriptReviewTeamMessageRowView.self)
            view.run = run
            view.onHeightInvalidated = heightInvalidationHandler(for: message.id, animatesLayoutChanges: false, configuration: configuration)
            view.configure(.init(message: message, bubbleMaxWidth: configuration.bubbleMaxWidth, typography: configuration.typography))
            return .init(id: message.id, view: view)
        }
    }
}

extension AppKitTranscriptRowFactory.Configuration {
    /// Resolved cards cannot adopt a newer proposal from the same conversation.
    func reviewState(for entry: HostToolWidgetEntry) -> ReviewProposalWidgetState? {
        (entry.reviewProposalID == nil ? nil : reviewProposalState(entry))
            ?? (entry.isUnresolvedReviewProposal ? conversationReviewProposal() : nil)
    }
}

/// A submitted review card's comment actions, by proposal id and then comment node id; Edit reports
/// whether GitHub took the new text, so the card knows whether to close its editor.
struct ReviewProposalPublishedCommentActions {
    var edit: @MainActor (String, String, String) async -> Bool = { _, _, _ in false }
    var delete: (String, String) -> Void = { _, _ in }
}

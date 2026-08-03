import AppKit

extension AppKitTranscriptRowFactory {
    func hostToolWidgetRow(
        id: String,
        entry: HostToolWidgetEntry,
        configuration: Configuration
    ) -> AppKitTranscriptLayoutRow {
        let view = cachedView(for: id, as: AppKitTranscriptHostToolWidgetRowView.self)
        view.onHeightInvalidated = heightInvalidationHandler(for: id, configuration: configuration)
        view.onConfirmScheduledProposal = configuration.onConfirmScheduledProposal
        view.onReviewScheduledProposal = configuration.onReviewScheduledProposal
        view.onRejectScheduledProposal = configuration.onRejectScheduledProposal
        view.onOpenScheduledTask = configuration.onOpenScheduledTask
        // A resolved widget must not adopt the conversation's *next* proposal, so the
        // conversation-scoped fallback only applies while this one is still unresolved.
        let presentation = entry.scheduledProposalID.flatMap(configuration.scheduledProposalPresentation)
            ?? (entry.isUnresolvedProposal ? configuration.conversationScheduledProposal() : nil)
        // The list tool's live rows double as the run-state feed; they already sit in
        // the bridge's content signature, so tense flips re-render without new wiring.
        let targetRow = entry.resolvedScheduledTaskID.flatMap { taskID in
            configuration.scheduledTaskListActions.rows().first { $0.id == taskID }
        }
        view.configure(
            .init(
                entry: entry,
                proposalPresentation: presentation,
                isProposalInteractive: presentation.map { configuration.isScheduledProposalInteractive($0.id) } ?? false,
                isResolving: configuration.isResolvingScheduledProposal,
                isTargetRunInFlight: targetRow?.hasActiveRun ?? false,
                errorMessage: configuration.scheduledProposalErrorMessage,
                bubbleMaxWidth: configuration.bubbleMaxWidth,
                typography: configuration.typography
            )
        )
        return .init(id: id, view: view)
    }
}

import Foundation

/// Resolve completion context only from the proposal's owner, never another review of the same PR.
extension PullRequestReviewProposalCoordinator {
    static func presentation(
        for record: PullRequestReviewProposalRecord,
        conversation: Conversation
    ) -> PullRequestReviewProposalPresentation? {
        guard let identifier = record.identifier,
              let event = PullRequestHostToolRequestParser.reviewEvent(from: record.event) else {
            return nil
        }
        return PullRequestReviewProposalPresentation(
            id: record.id,
            sourceConversationID: conversation.id,
            identifier: identifier,
            title: record.titleSnapshot,
            proposedEvent: event,
            body: record.body,
            comments: record.stagedComments,
            pendingCommentCount: record.pendingCommentCountSnapshot,
            reviewers: record.reviewers ?? [],
            collectiveCompletionWarning: collectiveCompletionWarning(for: record, conversation: conversation),
            createdAt: record.createdAt
        )
    }

    private static func collectiveCompletionWarning(for record: PullRequestReviewProposalRecord, conversation: Conversation) -> String? {
        guard record.sourceKind == .collectiveReview,
              let run = try? conversation.collectiveReviewRun(), run.proposalID == record.id else { return nil }
        return run.partialCompletionWarning
    }
}

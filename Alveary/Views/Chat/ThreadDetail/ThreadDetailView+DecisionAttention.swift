import SwiftUI

extension ThreadDetailView {
    /// Waiting-dot sources the runtime cannot report, so a conversation-tab chip agrees with its
    /// sidebar row.
    ///
    /// Read from `body`, where `conversationTabPresentations` consumes it: the coordinator sets
    /// behind it are observable state, and reading them from a child's body would register
    /// observation there instead, so this view would never re-evaluate. Same hazard the
    /// `statusVersion` parameter exists to work around for the non-observable `agentsManager`.
    var decisionAttention: ConversationDecisionAttention {
        ConversationDecisionAttention(
            approvals: unresolvedApprovalRegistry,
            scheduledProposals: scheduledTaskProposalQueueCoordinator,
            reviewProposals: pullRequestReviewProposalCoordinator,
            settings: settingsService.current
        )
    }
}

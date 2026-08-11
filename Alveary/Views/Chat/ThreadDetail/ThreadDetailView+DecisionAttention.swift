import SwiftUI

extension ThreadDetailView {
    /// Waiting-dot sources the runtime cannot report, so a conversation-tab chip agrees with its
    /// sidebar row.
    ///
    /// Read from `body`, never from inside the `statusForConversation` closure: that closure runs
    /// during `ThreadDetailConversationTabs`' body, so observation would register on the child and
    /// this view would never re-evaluate. Same hazard the `statusVersion` input exists to work
    /// around for the non-observable `agentsManager`.
    var decisionAttention: ConversationDecisionAttention {
        ConversationDecisionAttention(
            approvals: unresolvedApprovalRegistry,
            scheduledProposals: scheduledTaskProposalQueueCoordinator,
            reviewProposals: pullRequestReviewProposalCoordinator,
            settings: settingsService.current
        )
    }
}

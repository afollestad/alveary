import SwiftUI

/// The two status inputs no runtime `ActivitySignal` reports, built for the conversation-tab chips
/// from the same coordinators the sidebar rows read, so the two surfaces cannot disagree.
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

    /// Working-ring sources the runtime cannot report, so a chip spins alongside its sidebar row
    /// rather than showing the dot the same proposal raised while it was still pending.
    ///
    /// Read from `body` for the same reason as `decisionAttention` above, and for one more that
    /// `ConversationWorkActivity` owns: this read *is* the chip's repaint signal.
    var workActivity: ConversationWorkActivity {
        ConversationWorkActivity(reviewProposals: pullRequestReviewProposalCoordinator)
    }
}

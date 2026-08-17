import Foundation

/// Decisions a conversation is holding that no runtime `ActivitySignal` reports.
///
/// `DefaultAgentsManager` only knows a conversation is waiting when the provider process is
/// blocked on it — a permission prompt, `AskUserQuestion`, or `ExitPlanMode`. A proposal card or
/// a link question waits on the user just as much, but its turn completed normally, so the
/// runtime reports idle and the row would otherwise read as finished.
///
/// This is the single union of those sources, shared by the sidebar rows and the conversation-tab
/// chips so the two surfaces cannot disagree. A new awaiting-user transcript surface enrolls by
/// adding a source here, never by adding a second input to `ThreadStatus`.
struct ConversationDecisionAttention: Equatable {
    /// Prompts persisted with no answer, from `UnresolvedApprovalRegistry`. This is what survives
    /// relaunch; live prompts are already reported by the runtime.
    let unresolvedApprovalConversationIDs: Set<String>
    let scheduledProposalConversationIDs: Set<String>
    let reviewProposalConversationIDs: Set<String>
    /// `AppSettings.pullRequestsEnabled && !suppressPullRequestLinkPrompts`.
    let showsPullRequestLinkPrompts: Bool

    static let none = ConversationDecisionAttention(
        unresolvedApprovalConversationIDs: [],
        scheduledProposalConversationIDs: [],
        reviewProposalConversationIDs: [],
        showsPullRequestLinkPrompts: false
    )

    /// Both proposal sources are keyed by the conversation that opened them, which is also what
    /// makes a fork correct for free: it renders the same widget read-only and owns neither
    /// record, so it never claims the dot.
    ///
    /// Call only on a known-live row, during the pass that snapshots it into a
    /// `ConversationStatusSnapshot` — this reads persisted properties and a thread relationship,
    /// which trap on a deleted row. Render code consumes the snapshot, never this directly.
    func awaitsDecision(_ conversation: Conversation) -> Bool {
        let conversationID = conversation.id
        if unresolvedApprovalConversationIDs.contains(conversationID) ||
            scheduledProposalConversationIDs.contains(conversationID) ||
            reviewProposalConversationIDs.contains(conversationID) {
            return true
        }
        guard showsPullRequestLinkPrompts else {
            return false
        }
        return conversation.thread?.hasUnansweredPullRequestLinkPrompt(conversationID: conversationID) == true
    }
}

extension ConversationDecisionAttention {
    /// Assembles the live sources. Every surface showing the waiting dot builds it this way, so
    /// the sidebar and the conversation-tab chips cannot drift apart. The collaborators are
    /// optional because previews and snapshot hosts mount those views without the app root's
    /// environment; absent means "nothing pending", never a crash.
    ///
    /// Declared in an extension so the memberwise initializer above survives for tests.
    @MainActor
    init(
        approvals: UnresolvedApprovalRegistry?,
        scheduledProposals: ScheduledTaskProposalQueueCoordinator?,
        reviewProposals: PullRequestReviewProposalCoordinator?,
        settings: AppSettings
    ) {
        self.init(
            unresolvedApprovalConversationIDs: approvals?.conversationIDs ?? [],
            scheduledProposalConversationIDs: scheduledProposals?.pendingSourceConversationIDs ?? [],
            reviewProposalConversationIDs: reviewProposals?.pendingSourceConversationIDs ?? [],
            showsPullRequestLinkPrompts: settings.pullRequestsEnabled && !settings.suppressPullRequestLinkPrompts
        )
    }
}

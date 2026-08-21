import Foundation

/// Work a conversation is doing that no runtime `ActivitySignal` reports.
///
/// The sibling of `ConversationDecisionAttention`, and its opposite verdict. Both cover a
/// conversation whose provider turn already ended, so `DefaultAgentsManager` reports idle for
/// either: a proposal card waiting on the user is a decision, while the same proposal already
/// inside GitHub is the app working on the user's behalf. Folding the second as `.waitingForUser`
/// is what left a thread's row telling the user it was their turn for a whole submit.
///
/// A new such surface enrolls by adding a source here, never by adding a second input to
/// `ThreadStatus` — the rule `ConversationDecisionAttention` states for the waiting half.
struct ConversationWorkActivity: Equatable {
    /// From `PullRequestReviewProposalCoordinator.submittingSourceConversationIDs`.
    let publishingReviewConversationIDs: Set<String>

    static let none = ConversationWorkActivity(publishingReviewConversationIDs: [])

    /// Takes the id rather than the model, unlike `ConversationDecisionAttention.awaitsDecision(_:)`.
    /// Nothing here reads a persisted property or walks a relationship, so this carries none of that
    /// function's known-live-row contract; keep it that way rather than harmonizing the signatures.
    func isWorking(_ conversationID: String) -> Bool {
        publishingReviewConversationIDs.contains(conversationID)
    }
}

extension ConversationWorkActivity {
    /// Assembles the live sources, at the same two sites that build the decision half, so a sidebar
    /// row and its conversation-tab chip cannot disagree about which indicator a thread shows.
    ///
    /// **Build this in a view `body`, never behind a closure the fold calls later.** The coordinator
    /// is `@Observable`, so the read is what repaints the surface when a submit starts or ends;
    /// deferring it into `SidebarViewModel.threadStatus` or `ThreadStatus.folded`'s `runtimeFor:`
    /// would register the dependency on a `ForEach` element instead, and the row would never
    /// repaint. `runtimeFor:` is a closure only because `DefaultAgentsManager` is *not* observable
    /// and needs the `.agentStatusChanged` bump behind `statusVersion` instead.
    ///
    /// The collaborator is optional because previews and snapshot hosts mount those views without
    /// the app root's environment; absent means "nothing publishing", never a crash.
    ///
    /// Declared in an extension so the memberwise initializer above survives for tests.
    @MainActor
    init(reviewProposals: PullRequestReviewProposalCoordinator?) {
        self.init(
            publishingReviewConversationIDs: reviewProposals?.submittingSourceConversationIDs ?? []
        )
    }
}

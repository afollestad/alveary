import SwiftData
import SwiftUI

/// Builds the value snapshots the conversation tab strip renders from, and the ID-based actions
/// its chips hand back. `ConversationTabPresentation` owns why chips never hold models.
extension ThreadDetailView {
    /// One value per resolved conversation, built while the body pass's fetched rows are live.
    /// Chips and the ⌘W sink re-render from their own `@State` after this pass ends, so they may
    /// only hold these values.
    ///
    /// `statusVersion` is taken as a parameter so the *caller's* body registers the `@State`
    /// read: statuses come from the non-observable `agentsManager`, and the `.agentStatusChanged`
    /// bump is the only signal that they changed.
    func conversationTabPresentations(
        conversations: [Conversation],
        decisionAttention: ConversationDecisionAttention,
        statusVersion: Int
    ) -> [ConversationTabPresentation] {
        let isThreadArchived = liveThread?.archivedAt != nil
        return conversations.map { conversation in
            ConversationTabPresentation(
                conversation: conversation,
                status: .folded(
                    isArchived: isThreadArchived,
                    conversations: [
                        ConversationStatusSnapshot(conversation: conversation, attention: decisionAttention)
                    ],
                    runtimeFor: { agentsManager.status(for: $0) }
                )
            )
        }
    }

    func selectConversationTab(_ tab: ConversationTabPresentation) {
        guard let conversation = uiModelContext.resolveConversation(id: tab.conversationModelID) else {
            return
        }
        appState.selectConversation(conversation, in: thread)
    }

    /// `canRemove` is the presentation's snapshot; `removeConversation`'s commit-time guard stays
    /// the backstop for a value that went stale between the snapshot and the click.
    func requestRemoveConversationTab(_ tab: ConversationTabPresentation, tabCount: Int) {
        guard tabCount > 1, tab.canRemove else {
            return
        }
        pendingDeleteConversation = ThreadDetailPendingConversationRemoval(tab: tab)
    }
}

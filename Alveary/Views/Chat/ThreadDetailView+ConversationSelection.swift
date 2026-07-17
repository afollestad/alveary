import SwiftData

extension ThreadDetailView {
    /// Before deleting the selected tab, pick its visual neighbor (next,
    /// falling back to previous) instead of jumping to the main conversation.
    func selectNeighborIfClosingSelected(id: PersistentIdentifier, in dbThread: AgentThread) {
        let order = conversations
        guard appState.selectedConversation(in: dbThread, conversations: order)?.persistentModelID == id,
              let removedIndex = order.firstIndex(where: { $0.persistentModelID == id }) else {
            return
        }
        let neighbor: Conversation? = if removedIndex + 1 < order.count {
            order[removedIndex + 1]
        } else if removedIndex > 0 {
            order[removedIndex - 1]
        } else {
            nil
        }
        if let neighbor {
            appState.selectConversation(neighbor, in: dbThread)
        }
    }
}

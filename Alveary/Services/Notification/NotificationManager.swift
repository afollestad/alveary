@MainActor
protocol NotificationManager: AnyObject, Sendable {
    func handleEvent(_ event: ConversationEvent, conversationId: String)
    func markConversationRead(conversationId: String)
    func handleAppVisibilityChanged()
    func refreshBadgeCount()
    func setActiveConversationProvider(_ provider: @escaping @MainActor () -> String?)
}

extension NotificationManager {
    /// Async delete/archive flows may only have snapshotted conversation IDs after crossing
    /// an `await`, so offer an ID-based helper that doesn't require a live SwiftData model.
    func forgetConversations(withIDs conversationIds: [String]) {
        for conversationId in conversationIds {
            markConversationRead(conversationId: conversationId)
        }
    }
}

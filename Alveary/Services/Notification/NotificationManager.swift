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

    /// Dismiss any delivered banners and clear unread flags for every conversation in the given
    /// threads. Callers that archive or delete a thread or project must call this *before* the
    /// SwiftData mutation so the post-mark-read unread count lands on the chained badge task and
    /// no banner is orphaned in Notification Center.
    func forgetConversations(in threads: [AgentThread]) {
        forgetConversations(withIDs: threads.flatMap(\.conversations).map(\.id))
    }
}

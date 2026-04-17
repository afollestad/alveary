@MainActor
protocol NotificationManager: AnyObject, Sendable {
    func handleEvent(_ event: ConversationEvent, conversationId: String)
    func markConversationRead(conversationId: String)
    func handleAppVisibilityChanged()
    func refreshBadgeCount()
    func setActiveConversationProvider(_ provider: @escaping @MainActor () -> String?)
}

extension NotificationManager {
    /// Dismiss any delivered banners and clear unread flags for every conversation in the given
    /// threads. Callers that archive or delete a thread or project must call this *before* the
    /// SwiftData mutation so the post-mark-read unread count lands on the chained badge task and
    /// no banner is orphaned in Notification Center.
    func forgetConversations(in threads: [AgentThread]) {
        for thread in threads {
            for conversation in thread.conversations {
                markConversationRead(conversationId: conversation.id)
            }
        }
    }
}

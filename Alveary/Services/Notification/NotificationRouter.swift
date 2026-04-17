import Foundation

@MainActor
@Observable
final class NotificationRouter {
    var pendingConversationId: String?

    func requestOpen(conversationId: String) {
        pendingConversationId = conversationId
    }

    func clearPendingIfMatches(_ conversationId: String) {
        guard pendingConversationId == conversationId else {
            return
        }
        pendingConversationId = nil
    }
}

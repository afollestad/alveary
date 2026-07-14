import Foundation

@MainActor
@Observable
final class NotificationRouter {
    var pendingConversationId: String?
    var pendingScheduledTaskDefinitionId: String?

    func requestOpen(conversationId: String) {
        pendingConversationId = conversationId
    }

    func clearPendingIfMatches(_ conversationId: String) {
        guard pendingConversationId == conversationId else {
            return
        }
        pendingConversationId = nil
    }

    func requestOpenScheduledTask(definitionId: String) {
        pendingScheduledTaskDefinitionId = definitionId
    }

    func clearPendingScheduledTaskIfMatches(_ definitionId: String) {
        guard pendingScheduledTaskDefinitionId == definitionId else {
            return
        }
        pendingScheduledTaskDefinitionId = nil
    }
}

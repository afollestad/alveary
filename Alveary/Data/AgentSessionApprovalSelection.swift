import Foundation
import SwiftData

@Model
final class AgentSessionApprovalSelection {
    // Remembers the last split-button choice for a Claude session; this is not an approval grant.
    var providerId: String
    var conversationId: String
    var sessionId: String
    var selection: String
    var updatedAt: Date

    init(
        providerId: String,
        conversationId: String,
        sessionId: String,
        selection: String,
        updatedAt: Date = Date()
    ) {
        self.providerId = providerId
        self.conversationId = conversationId
        self.sessionId = sessionId
        self.selection = selection
        self.updatedAt = updatedAt
    }
}

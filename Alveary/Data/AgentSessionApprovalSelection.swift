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

    /// Keeps the existing SwiftData column while exposing harness terminology.
    var harnessId: String {
        get { providerId }
        set { providerId = newValue }
    }

    init(
        harnessId: String,
        conversationId: String,
        sessionId: String,
        selection: String,
        updatedAt: Date = Date()
    ) {
        self.providerId = harnessId
        self.conversationId = conversationId
        self.sessionId = sessionId
        self.selection = selection
        self.updatedAt = updatedAt
    }
}

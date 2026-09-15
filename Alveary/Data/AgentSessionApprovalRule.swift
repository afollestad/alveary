import Foundation
import SwiftData

@Model
final class AgentSessionApprovalRule {
    var providerId: String
    var conversationId: String
    var sessionId: String
    var matchKind: String
    var matchValue: String
    var createdAt: Date

    /// Keeps the existing SwiftData column while exposing harness terminology.
    var harnessId: String {
        get { providerId }
        set { providerId = newValue }
    }

    init(
        harnessId: String,
        conversationId: String,
        sessionId: String,
        matchKind: String,
        matchValue: String,
        createdAt: Date = Date()
    ) {
        self.providerId = harnessId
        self.conversationId = conversationId
        self.sessionId = sessionId
        self.matchKind = matchKind
        self.matchValue = matchValue
        self.createdAt = createdAt
    }
}

import Foundation
import SwiftData

@testable import Alveary

/// Frozen schema before project folders; initializer values do not change the stored schema.
extension PreProjectFoldersSchema {
    @Model
    final class ScheduledTaskProposal {
        static let currentPayloadVersion = 1
        @Attribute(.unique) var id: String
        @Attribute(.unique) var sourceConversationID: String
        @Attribute(.unique) var deduplicationKey: String
        var payloadVersion: Int = ScheduledTaskProposal.currentPayloadVersion
        var actionRawValue: String
        var canonicalPayloadJSON: String
        var canonicalPayloadHash: String
        var sourceProviderID: String
        var sourceProcessToken: String
        var sourceRequestID: String
        var targetDefinitionID: String?
        var expectedDefinitionRevision: Int?
        var targetTitleSnapshot: String?
        var targetScheduleSummarySnapshot: String?
        var definitionDraftJSON: String?
        var projectPathSnapshot: String?
        var enqueueOrdinal: Int64?
        var createdAt: Date
        var sourceConversation: Conversation?
        var project: Project?

        init() {
            self.id = ""
            self.sourceConversationID = ""
            self.deduplicationKey = ""
            self.payloadVersion = 0
            self.actionRawValue = ""
            self.canonicalPayloadJSON = ""
            self.canonicalPayloadHash = ""
            self.sourceProviderID = ""
            self.sourceProcessToken = ""
            self.sourceRequestID = ""
            self.targetDefinitionID = nil
            self.expectedDefinitionRevision = nil
            self.targetTitleSnapshot = nil
            self.targetScheduleSummarySnapshot = nil
            self.definitionDraftJSON = nil
            self.projectPathSnapshot = nil
            self.enqueueOrdinal = nil
            self.createdAt = Date(timeIntervalSince1970: 0)
            self.sourceConversation = nil
            self.project = nil
        }
    }
}

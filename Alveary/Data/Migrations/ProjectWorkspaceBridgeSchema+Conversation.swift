import Foundation
import SwiftData

/// Frozen additive bridge from pre-folder stores. Change current models instead of these declarations.
extension ProjectWorkspaceBridgeSchema {
    @Model
    final class Conversation {
        @Attribute(.unique) var id: String
        var title: String?
        var provider: String?
        var providerSessionId: String?
        var providerSessionProviderId: String?
        var providerSessionWorkingDirectory: String?
        var pendingRestoreContext: String?
        var scheduledTaskProposalReceiptsJSON: String?
        var threadHostToolReceiptsJSON: String?
        var pullRequestHostToolReceiptsJSON: String?
        var pullRequestReviewProposalJSON: String?
        var pullRequestReviewRunJSON: String?
        var lastTurnFailedAt: Date?
        var isActive: Bool
        var isMain: Bool
        var displayOrder: Int
        var isUnread: Bool
        var thread: AgentThread?
        @Relationship(deleteRule: .cascade, inverse: \ConversationEventRecord.conversation) var events: [ConversationEventRecord]
        @Relationship(deleteRule: .cascade, inverse: \ScheduledTaskProposal.sourceConversation) var scheduledTaskProposals: [ScheduledTaskProposal]

        init() {
            self.id = ""
            self.title = nil
            self.provider = nil
            self.providerSessionId = nil
            self.providerSessionProviderId = nil
            self.providerSessionWorkingDirectory = nil
            self.pendingRestoreContext = nil
            self.scheduledTaskProposalReceiptsJSON = nil
            self.threadHostToolReceiptsJSON = nil
            self.pullRequestHostToolReceiptsJSON = nil
            self.pullRequestReviewProposalJSON = nil
            self.pullRequestReviewRunJSON = nil
            self.lastTurnFailedAt = nil
            self.isActive = false
            self.isMain = false
            self.displayOrder = 0
            self.isUnread = false
            self.thread = nil
            self.events = []
            self.scheduledTaskProposals = []
        }
    }
}

import SwiftData

/// Stored schema before project folders, including the subsequently added review-team run history.
enum PreProjectFoldersSchema: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Project.self, AgentThread.self, SidebarSection.self, Conversation.self,
         ConversationEventRecord.self, ScheduledTask.self, ScheduledTaskRun.self, ScheduledTaskProposal.self]
    }
}

import Foundation
import SwiftData

// Stored-schema snapshot of commit a61750. Keep this frozen so migration tests
// create a real pre-Task-mode store instead of silently adopting current fields.
enum PreTaskModeSchema: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Project.self, AgentThread.self, Conversation.self, ConversationEventRecord.self]
    }

    @Model
    final class Project {
        @Attribute(.unique) var path: String
        var name: String
        var gitRemote: String?
        var remoteName: String?
        var gitBranch: String?
        var baseRef: String?
        var githubRepository: String?
        var githubConnected: Bool
        var isPinned: Bool = false
        var sidebarSortOrder: Int?
        var pinnedSortOrder: Int?
        @Relationship(deleteRule: .cascade, inverse: \AgentThread.project) var threads: [AgentThread]

        init(path: String, name: String, threads: [AgentThread] = []) {
            self.path = path
            self.name = name
            self.gitRemote = nil
            self.remoteName = nil
            self.gitBranch = nil
            self.baseRef = nil
            self.githubRepository = nil
            self.githubConnected = false
            self.sidebarSortOrder = nil
            self.pinnedSortOrder = nil
            self.threads = threads
        }
    }

    @Model
    final class AgentThread {
        var name: String
        var hasCustomName: Bool
        var branch: String?
        var pendingCleanupBranches: [String]
        var worktreePath: String?
        var hasCompletedInitialSetup: Bool
        var permissionMode: String
        var planModeEnabled: Bool?
        var effort: String
        var model: String?
        var speedMode: String?
        var useWorktree: Bool
        var isPinned: Bool = false
        var pinnedSortOrder: Int?
        var isDraft: Bool = false
        var modifiedAt: Date?
        var archivedAt: Date?
        var project: Project?
        @Relationship(deleteRule: .cascade, inverse: \Conversation.thread) var conversations: [Conversation]

        init(name: String, project: Project? = nil, conversations: [Conversation] = []) {
            self.name = name
            self.hasCustomName = false
            self.branch = nil
            self.pendingCleanupBranches = []
            self.worktreePath = nil
            self.hasCompletedInitialSetup = false
            self.permissionMode = "default"
            self.planModeEnabled = false
            self.effort = "medium"
            self.model = nil
            self.speedMode = "standard"
            self.useWorktree = false
            self.pinnedSortOrder = nil
            self.modifiedAt = nil
            self.archivedAt = nil
            self.project = project
            self.conversations = conversations
        }
    }

    @Model
    final class Conversation {
        @Attribute(.unique) var id: String
        var title: String?
        var provider: String?
        var providerSessionId: String?
        var providerSessionProviderId: String?
        var providerSessionWorkingDirectory: String?
        var pendingRestoreContext: String?
        var isActive: Bool
        var isMain: Bool
        var displayOrder: Int
        var isUnread: Bool
        var thread: AgentThread?
        @Relationship(deleteRule: .cascade, inverse: \ConversationEventRecord.conversation) var events: [ConversationEventRecord]

        init(id: String, thread: AgentThread? = nil, events: [ConversationEventRecord] = []) {
            self.id = id
            self.title = nil
            self.provider = "claude"
            self.providerSessionId = nil
            self.providerSessionProviderId = nil
            self.providerSessionWorkingDirectory = nil
            self.pendingRestoreContext = nil
            self.isActive = true
            self.isMain = true
            self.displayOrder = 0
            self.isUnread = false
            self.thread = thread
            self.events = events
        }
    }

    @Model
    final class ConversationEventRecord {
        #Index<ConversationEventRecord>([\.conversationId, \.timestamp])

        @Attribute(.unique) var id: String
        var conversationId: String
        var type: String
        var role: String?
        var content: String?
        var transcriptAttachmentsJSON: String?
        var toolId: String?
        var toolName: String?
        var toolInput: String?
        var toolApprovalStatus: String?
        var toolOutput: String?
        var toolOutputStderr: String?
        var toolOutputInterrupted: Bool
        var toolOutputIsImage: Bool
        var toolOutputNoOutputExpected: Bool
        var parentToolUseId: String?
        var callerAgent: String?
        var isError: Bool
        var tokenInput: Int
        var tokenOutput: Int
        var tokenCacheRead: Int
        var tokenCacheCreation: Int = 0
        var durationMs: Int
        var costUsd: Double
        var costUsdReported: Bool = false
        var providerModelId: String?
        var contextWindowSize: Int?
        var notificationType: String?
        var stopReason: String?
        var timestamp: Date
        var conversation: Conversation?

        init(id: String, conversationId: String, conversation: Conversation? = nil) {
            self.id = id
            self.conversationId = conversationId
            self.type = "message"
            self.role = "user"
            self.content = "Legacy message"
            self.transcriptAttachmentsJSON = nil
            self.toolId = nil
            self.toolName = nil
            self.toolInput = nil
            self.toolApprovalStatus = nil
            self.toolOutput = nil
            self.toolOutputStderr = nil
            self.toolOutputInterrupted = false
            self.toolOutputIsImage = false
            self.toolOutputNoOutputExpected = false
            self.parentToolUseId = nil
            self.callerAgent = nil
            self.isError = false
            self.tokenInput = 0
            self.tokenOutput = 0
            self.tokenCacheRead = 0
            self.durationMs = 0
            self.costUsd = 0
            self.providerModelId = nil
            self.contextWindowSize = nil
            self.notificationType = nil
            self.stopReason = nil
            self.timestamp = Date(timeIntervalSince1970: 1)
            self.conversation = conversation
        }
    }
}

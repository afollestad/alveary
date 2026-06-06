import Foundation
import SwiftData

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
    var useWorktree: Bool
    var archivedAt: Date?
    var project: Project?
    @Relationship(deleteRule: .cascade, inverse: \Conversation.thread) var conversations: [Conversation]

    init(
        name: String,
        hasCustomName: Bool = false,
        branch: String? = nil,
        pendingCleanupBranches: [String] = [],
        worktreePath: String? = nil,
        hasCompletedInitialSetup: Bool = false,
        permissionMode: String = "default",
        planModeEnabled: Bool = false,
        effort: String = AppSettings.defaultEffortLevel,
        model: String? = nil,
        useWorktree: Bool = false,
        archivedAt: Date? = nil,
        project: Project? = nil,
        conversations: [Conversation] = []
    ) {
        self.name = name
        self.hasCustomName = hasCustomName
        self.branch = branch
        self.pendingCleanupBranches = pendingCleanupBranches
        self.worktreePath = worktreePath.map(CanonicalPath.normalize)
        self.hasCompletedInitialSetup = hasCompletedInitialSetup
        self.permissionMode = permissionMode
        self.planModeEnabled = planModeEnabled
        self.effort = effort
        self.model = model
        self.useWorktree = useWorktree
        self.archivedAt = archivedAt
        self.project = project
        self.conversations = conversations
    }
}

extension AgentThread {
    func prepareForRestore() {
        for conversation in conversations {
            conversation.refreshPendingRestoreContextFromHistory()
        }
        archivedAt = nil
    }
}

import Foundation
import SwiftData

/// Frozen additive bridge from pre-folder stores. Change current models instead of these declarations.
extension ProjectWorkspaceBridgeSchema {
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
        var isForkBootstrapPending: Bool = false
        var modifiedAt: Date?
        var archivedAt: Date?
        var modeRawValue: String = AgentThreadMode.project.rawValue
        var taskPrimaryRoot: String?
        var taskGrantedRoots: [String] = []
        var taskWorkspaceOwnershipStrategyRawValue: String?
        var taskWorkspaceMarkerID: String?
        var taskSourceProjectPath: String?
        var linkedPullRequestsJSON: String?
        var pendingPullRequestPromptsJSON: String?
        var pullRequestScanWatermark: Date?
        var project: Project?
        var customSection: SidebarSection?
        var scheduledTaskRun: ScheduledTaskRun?
        @Relationship(deleteRule: .nullify, inverse: \ScheduledTask.targetThread)
        var targetedScheduledTasks: [ScheduledTask] = []
        @Relationship(deleteRule: .nullify, inverse: \ScheduledTask.reusedThread)
        var reusingScheduledTasks: [ScheduledTask] = []
        @Relationship(deleteRule: .nullify, inverse: \ScheduledTaskRun.targetThread)
        var targetedScheduledTaskRuns: [ScheduledTaskRun] = []
        @Relationship(deleteRule: .cascade, inverse: \Conversation.thread) var conversations: [Conversation]
        var workspaceSnapshotJSON: String?

        init() {
            self.name = ""
            self.hasCustomName = false
            self.branch = nil
            self.pendingCleanupBranches = []
            self.worktreePath = nil
            self.hasCompletedInitialSetup = false
            self.permissionMode = ""
            self.planModeEnabled = nil
            self.effort = ""
            self.model = nil
            self.speedMode = nil
            self.useWorktree = false
            self.isPinned = false
            self.pinnedSortOrder = nil
            self.isDraft = false
            self.isForkBootstrapPending = false
            self.modifiedAt = nil
            self.archivedAt = nil
            self.modeRawValue = ""
            self.taskPrimaryRoot = nil
            self.taskGrantedRoots = []
            self.taskWorkspaceOwnershipStrategyRawValue = nil
            self.taskWorkspaceMarkerID = nil
            self.taskSourceProjectPath = nil
            self.linkedPullRequestsJSON = nil
            self.pendingPullRequestPromptsJSON = nil
            self.pullRequestScanWatermark = nil
            self.project = nil
            self.customSection = nil
            self.scheduledTaskRun = nil
            self.targetedScheduledTasks = []
            self.reusingScheduledTasks = []
            self.targetedScheduledTaskRuns = []
            self.conversations = []
            self.workspaceSnapshotJSON = nil
        }
    }
}

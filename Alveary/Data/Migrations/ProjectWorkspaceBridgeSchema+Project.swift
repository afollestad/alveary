import Foundation
import SwiftData

/// Frozen additive bridge from pre-folder stores. Change current models instead of these declarations.
extension ProjectWorkspaceBridgeSchema {
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
        var linkedPullRequestsJSON: String?
        @Relationship(deleteRule: .cascade, inverse: \AgentThread.project) var threads: [AgentThread]
        @Relationship(deleteRule: .nullify, inverse: \ScheduledTask.project) var scheduledTasks: [ScheduledTask]
        @Relationship(deleteRule: .nullify, inverse: \ScheduledTaskProposal.project) var scheduledTaskProposals: [ScheduledTaskProposal]
        var id: String?
        var primaryFolderID: String?
        @Relationship(deleteRule: .cascade, inverse: \ProjectFolder.project) var folders: [ProjectFolder] = []

        init() {
            self.path = ""
            self.name = ""
            self.gitRemote = nil
            self.remoteName = nil
            self.gitBranch = nil
            self.baseRef = nil
            self.githubRepository = nil
            self.githubConnected = false
            self.isPinned = false
            self.sidebarSortOrder = nil
            self.pinnedSortOrder = nil
            self.linkedPullRequestsJSON = nil
            self.threads = []
            self.scheduledTasks = []
            self.scheduledTaskProposals = []
            self.id = nil
            self.primaryFolderID = nil
            self.folders = []
        }
    }
}

import Foundation
import SwiftData

@testable import Alveary

/// Frozen schema before project folders; initializer values do not change the stored schema.
extension PreProjectFoldersSchema {
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
        }
    }
}

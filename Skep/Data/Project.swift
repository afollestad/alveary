import SwiftData

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
    @Relationship(deleteRule: .cascade, inverse: \AgentThread.project) var threads: [AgentThread]

    init(
        path: String,
        name: String,
        gitRemote: String? = nil,
        remoteName: String? = nil,
        gitBranch: String? = nil,
        baseRef: String? = nil,
        githubRepository: String? = nil,
        githubConnected: Bool = false,
        threads: [AgentThread] = []
    ) {
        self.path = CanonicalPath.normalize(path)
        self.name = name
        self.gitRemote = gitRemote
        self.remoteName = remoteName
        self.gitBranch = gitBranch
        self.baseRef = baseRef
        self.githubRepository = githubRepository
        self.githubConnected = githubConnected
        self.threads = threads
    }
}

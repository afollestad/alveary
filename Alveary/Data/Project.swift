import Foundation
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

    var isGitRepository: Bool {
        gitBranch != nil || baseRef != nil || remoteName != nil || gitRemote != nil || githubRepository != nil
    }

    var githubRepositoryURL: URL? {
        guard let githubRepository else {
            return nil
        }

        return URL(string: "https://github.com/\(githubRepository)")
    }

    static func parseGitHubRepository(from remoteURL: String) -> String? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)

        if let scpPath = parseGitHubSCPPath(from: trimmed) {
            return normalizeGitHubRepositoryPath(scpPath)
        }

        guard let components = URLComponents(string: trimmed),
              let host = components.host?.lowercased(),
              host == "github.com" || host == "www.github.com" else {
            return nil
        }

        return normalizeGitHubRepositoryPath(components.path)
    }

    private static func parseGitHubSCPPath(from remoteURL: String) -> String? {
        guard !remoteURL.contains("://"),
              let separatorIndex = remoteURL.firstIndex(of: ":") else {
            return nil
        }

        let authority = String(remoteURL[..<separatorIndex])
        let host = authority
            .split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
            .last
            .map(String.init)?
            .lowercased()

        guard host == "github.com" || host == "www.github.com" else {
            return nil
        }

        let pathStartIndex = remoteURL.index(after: separatorIndex)
        let path = String(remoteURL[pathStartIndex...])
        return path.isEmpty ? nil : path
    }

    private static func normalizeGitHubRepositoryPath(_ path: String) -> String? {
        let parts = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard parts.count >= 2 else {
            return nil
        }

        let owner = parts[0]
        let repo = parts[1].hasSuffix(".git")
            ? String(parts[1].dropLast(4))
            : parts[1]
        guard !owner.isEmpty, !repo.isEmpty else {
            return nil
        }
        return "\(owner)/\(repo)"
    }
}

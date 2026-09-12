import Foundation
import SwiftData

@Model
final class Project {
    @Attribute(.unique) var id: String
    var name: String
    var primaryFolderID: String?
    @Relationship(deleteRule: .cascade, inverse: \ProjectFolder.project) var folders: [ProjectFolder]
    var isPinned: Bool = false
    var sidebarSortOrder: Int?
    var pinnedSortOrder: Int?
    /// JSON-encoded `LinkedPullRequest` list; see `Project+PullRequestLinks.swift`.
    /// Optional with no `init` parameter so pre-field stores migrate as unlinked.
    var linkedPullRequestsJSON: String?
    @Relationship(deleteRule: .cascade, inverse: \AgentThread.project) var threads: [AgentThread]
    @Relationship(deleteRule: .nullify, inverse: \ScheduledTask.project) var scheduledTasks: [ScheduledTask]
    @Relationship(deleteRule: .nullify, inverse: \ScheduledTaskProposal.project) var scheduledTaskProposals: [ScheduledTaskProposal]

    init(
        path: String? = nil,
        name: String,
        gitRemote: String? = nil,
        remoteName: String? = nil,
        gitBranch: String? = nil,
        baseRef: String? = nil,
        githubRepository: String? = nil,
        githubConnected: Bool = false,
        isPinned: Bool = false,
        sidebarSortOrder: Int? = nil,
        pinnedSortOrder: Int? = nil,
        id: String = UUID().uuidString,
        folders: [SourceFolderSnapshot]? = nil,
        primaryFolderPath: String? = nil,
        threads: [AgentThread] = [],
        scheduledTasks: [ScheduledTask] = [],
        scheduledTaskProposals: [ScheduledTaskProposal] = []
    ) {
        self.id = id
        self.name = name
        let sources = folders ?? path.map {
            [SourceFolderSnapshot(
                path: CanonicalPath.normalize($0), gitRemote: gitRemote, remoteName: remoteName,
                gitBranch: gitBranch, baseRef: baseRef, githubRepository: githubRepository, githubConnected: githubConnected
            )]
        } ?? []
        var seen = Set<String>()
        let memberships = sources.filter { seen.insert($0.path).inserted }.enumerated().map {
            ProjectFolder(snapshot: $0.element, sortOrder: $0.offset)
        }
        self.folders = memberships
        self.primaryFolderID = memberships.first(where: { $0.path == primaryFolderPath })?.id ?? memberships.first?.id
        self.isPinned = isPinned
        self.sidebarSortOrder = sidebarSortOrder
        self.pinnedSortOrder = pinnedSortOrder
        self.threads = threads
        self.scheduledTasks = scheduledTasks
        self.scheduledTaskProposals = scheduledTaskProposals
    }

    var orderedFolders: [ProjectFolder] {
        folders.sorted { $0.sortOrder == $1.sortOrder ? $0.id < $1.id : $0.sortOrder < $1.sortOrder }
    }

    var primaryFolder: ProjectFolder? {
        orderedFolders.first { $0.id == primaryFolderID } ?? orderedFolders.first
    }

    func workspaceSnapshot(primaryPath: String? = nil) -> WorkspaceSnapshot {
        let sources = orderedFolders.map(\.snapshot)
        let primary = sources.first { $0.path == primaryPath } ?? primaryFolder?.snapshot
        return WorkspaceSnapshot(primarySource: primary, grants: sources.filter { $0.path != primary?.path })
    }

    // Source-folder conveniences for project-only surfaces. Thread consumers use their saved workspace.
    var path: String { primaryFolder?.path ?? "" }
    var gitRemote: String? {
        get { primaryFolder?.gitRemote }
        set { primaryFolder?.gitRemote = newValue }
    }
    var remoteName: String? {
        get { primaryFolder?.remoteName }
        set { primaryFolder?.remoteName = newValue }
    }
    var gitBranch: String? {
        get { primaryFolder?.gitBranch }
        set { primaryFolder?.gitBranch = newValue }
    }
    var baseRef: String? {
        get { primaryFolder?.baseRef }
        set { primaryFolder?.baseRef = newValue }
    }
    var githubRepository: String? {
        get { primaryFolder?.githubRepository }
        set { primaryFolder?.githubRepository = newValue }
    }
    var githubConnected: Bool {
        get { primaryFolder?.githubConnected ?? false }
        set { primaryFolder?.githubConnected = newValue }
    }
    var isGitRepository: Bool { primaryFolder?.snapshot.isGitRepository ?? false }
    var githubRepositoryURL: URL? {
        githubRepository.flatMap { URL(string: "https://github.com/\($0)") }
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

extension Project {
    var workspaceFolderTargets: [WorkspaceFolderTarget] {
        orderedFolders.map {
            WorkspaceFolderTarget(directory: $0.path, source: $0.snapshot, isPrimary: $0.id == primaryFolder?.id)
        }
    }
}

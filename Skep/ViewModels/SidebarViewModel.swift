import Foundation
import Observation
import SwiftData

enum ThreadStatus: Sendable, Equatable {
    case busy
    case idle
    case stopped
    case error
    case archived
}

@MainActor
@Observable
final class SidebarViewModel {
    private let agentsManager: any AgentsManager
    private let modelContext: ModelContext
    private let shell: ShellRunner
    private let gitHubCLI: GitHubCLIService
    private let worktreeManager: WorktreeManager
    private let settingsService: SettingsService
    private var statusObserver: NSObjectProtocol?

    private(set) var sidebarError: String?
    private(set) var statusVersion = 0

    init(
        agentsManager: any AgentsManager,
        modelContext: ModelContext,
        shell: ShellRunner,
        gitHubCLI: GitHubCLIService,
        worktreeManager: WorktreeManager,
        settingsService: SettingsService
    ) {
        self.agentsManager = agentsManager
        self.modelContext = modelContext
        self.shell = shell
        self.gitHubCLI = gitHubCLI
        self.worktreeManager = worktreeManager
        self.settingsService = settingsService

        statusObserver = NotificationCenter.default.addObserver(
            forName: .agentStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.statusVersion += 1
            }
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if let statusObserver {
                NotificationCenter.default.removeObserver(statusObserver)
            }
        }
    }

    func createProject(path: String) async throws -> Project {
        let projectPath = try await gitOutput(
            args: ["rev-parse", "--show-toplevel"],
            in: path
        )
        let currentBranch = try await gitOutput(
            args: ["rev-parse", "--abbrev-ref", "HEAD"],
            in: projectPath
        )
        let remoteName = try await resolvePreferredRemoteName(
            in: projectPath,
            currentBranch: currentBranch
        )
        let remoteURL = try await resolveRemoteURL(in: projectPath, remoteName: remoteName)
        let githubRepository = remoteURL.flatMap(Self.parseGitHubRepository(from:))
        let githubConnected = await resolveGitHubConnectionState(for: githubRepository)
        let baseRef = try await resolveBaseRef(
            in: projectPath,
            remoteName: remoteName,
            fallbackBranch: currentBranch
        )

        // Load the shared repo config once during import so later settings/worktree flows
        // reuse the same parse path. Invalid JSON intentionally degrades to defaults.
        _ = await SkepProjectConfig(projectPath: projectPath)

        let project = Project(
            path: projectPath,
            name: URL(fileURLWithPath: projectPath).lastPathComponent,
            gitRemote: remoteURL,
            remoteName: remoteName,
            gitBranch: currentBranch,
            baseRef: baseRef,
            githubRepository: githubRepository,
            githubConnected: githubConnected
        )
        modelContext.insert(project)
        try modelContext.save()
        return project
    }

    func createThread(project: Project, provider: String, permissionMode: String) async throws -> AgentThread {
        let dbProject = try requireProject(project)
        let thread = AgentThread(
            name: "New thread",
            permissionMode: permissionMode,
            effort: settingsService.current.effort,
            useWorktree: settingsService.current.createWorktreeByDefault,
            project: dbProject
        )
        let conversation = Conversation(
            provider: provider,
            isMain: true,
            displayOrder: 0,
            thread: thread
        )

        modelContext.insert(thread)
        modelContext.insert(conversation)
        try modelContext.save()
        return thread
    }

    func createThread(project: Project) async throws -> AgentThread {
        try await createThread(
            project: project,
            provider: settingsService.current.defaultProvider,
            permissionMode: settingsService.current.permissionMode
        )
    }

    func presentSidebarError(_ error: Error) {
        sidebarError = error.localizedDescription
    }

    func dismissSidebarError() {
        sidebarError = nil
    }

    func archiveThread(_ thread: AgentThread) async throws {
        let dbThread = try requireThread(thread)
        try await quiesceThreadConversations(dbThread)
        dbThread.archivedAt = Date()
        try modelContext.save()
    }

    func restoreThread(_ thread: AgentThread) throws {
        let dbThread = try requireThread(thread)
        dbThread.archivedAt = nil
        try modelContext.save()
    }

    func deleteThread(_ thread: AgentThread) async throws {
        let dbThread = try requireThread(thread)
        try await quiesceThreadConversations(dbThread)

        guard let projectPath = dbThread.project?.path else {
            throw SidebarViewModelError.threadMissingParentProject
        }

        for pendingCleanupBranch in dbThread.pendingCleanupBranches
        where pendingCleanupBranch != dbThread.branch {
            try await worktreeManager.deleteBranch(
                projectPath: projectPath,
                branch: pendingCleanupBranch
            )
        }

        let requiresCompletedWorktreeCleanup = dbThread.useWorktree && dbThread.hasCompletedInitialSetup
        if requiresCompletedWorktreeCleanup {
            guard let worktreePath = dbThread.worktreePath,
                  let branch = dbThread.branch else {
                throw SidebarViewModelError.threadMissingDeletionMetadata
            }
            try await worktreeManager.remove(
                projectPath: projectPath,
                worktreePath: worktreePath,
                branch: branch
            )
        } else if let worktreePath = dbThread.worktreePath {
            try await worktreeManager.remove(
                projectPath: projectPath,
                worktreePath: worktreePath,
                branch: dbThread.branch
            )
        } else if dbThread.branch != nil {
            throw SidebarViewModelError.threadMissingDeletionMetadata
        }

        modelContext.delete(dbThread)
        try modelContext.save()
    }

    func threadStatus(for thread: AgentThread) -> ThreadStatus {
        if thread.archivedAt != nil {
            return .archived
        }

        var hasError = false
        var hasIdle = false
        var hasStopped = false

        for conversation in thread.conversations {
            switch agentsManager.status(for: conversation.id) {
            case .busy:
                return .busy
            case .error:
                hasError = true
            case .idle:
                hasIdle = true
            case .stopped:
                hasStopped = true
            case .neutral:
                break
            }
        }

        if hasError {
            return .error
        }
        if hasIdle {
            return .idle
        }
        if hasStopped {
            return .stopped
        }
        return .stopped
    }
}

private extension SidebarViewModel {
    func requireProject(_ project: Project) throws -> Project {
        let path = project.path
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { candidate in
                candidate.path == path
            }
        )

        guard let dbProject = try modelContext.fetch(descriptor).first else {
            throw SidebarViewModelError.projectMissing
        }
        return dbProject
    }

    func requireThread(_ thread: AgentThread) throws -> AgentThread {
        guard let dbThread = modelContext.model(for: thread.persistentModelID) as? AgentThread else {
            throw SidebarViewModelError.threadMissing
        }
        return dbThread
    }

    func quiesceThreadConversations(_ thread: AgentThread) async throws {
        let conversationIds = thread.conversations.map(\.id)
        var firstError: Error?

        for conversationId in conversationIds {
            do {
                try await agentsManager.destroyRuntime(conversationId: conversationId)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if let firstError {
            throw firstError
        }
    }

    func resolvePreferredRemoteName(in directory: String, currentBranch: String) async throws -> String? {
        if let upstreamRemote = try await optionalGitOutput(
            args: ["for-each-ref", "--format=%(upstream:remotename)", "refs/heads/\(currentBranch)"],
            in: directory
        ) {
            return upstreamRemote
        }

        let remotes = try await gitOutput(args: ["remote"], in: directory)
            .split(separator: "\n")
            .map(String.init)

        if remotes.count == 1 {
            return remotes[0]
        }
        if remotes.contains("origin") {
            return "origin"
        }
        return nil
    }

    func resolveRemoteURL(in directory: String, remoteName: String?) async throws -> String? {
        guard let remoteName else {
            return nil
        }
        return try await gitOutput(args: ["remote", "get-url", remoteName], in: directory)
    }

    func resolveGitHubConnectionState(for githubRepository: String?) async -> Bool {
        guard githubRepository != nil else {
            return false
        }
        guard await gitHubCLI.checkInstalled() != nil else {
            return false
        }
        return await gitHubCLI.isAuthenticated()
    }

    func resolveBaseRef(
        in directory: String,
        remoteName: String?,
        fallbackBranch: String
    ) async throws -> String {
        guard let remoteName,
              let remoteHead = try await optionalGitOutput(
                  args: ["symbolic-ref", "refs/remotes/\(remoteName)/HEAD"],
                  in: directory
              ),
              let baseRef = parseRemoteHead(remoteHead, remoteName: remoteName) else {
            return fallbackBranch
        }

        return baseRef
    }

    func gitOutput(args: [String], in directory: String?) async throws -> String {
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: args,
            in: directory
        )
        guard result.succeeded else {
            throw makeGitError(from: result)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func optionalGitOutput(args: [String], in directory: String?) async throws -> String? {
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: args,
            in: directory
        )
        guard result.succeeded else {
            return nil
        }

        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    func parseRemoteHead(_ remoteHead: String, remoteName: String) -> String? {
        let prefix = "refs/remotes/\(remoteName)/"
        guard remoteHead.hasPrefix(prefix) else {
            return nil
        }

        let baseRef = String(remoteHead.dropFirst(prefix.count))
        return baseRef.isEmpty ? nil : baseRef
    }

    func makeGitError(from result: ShellResult) -> GitError {
        let combined = [result.stderr, result.stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? "Git command failed"

        if combined.localizedCaseInsensitiveContains("not a git repository") {
            return .notARepository
        }
        return .commandFailed(combined)
    }

    static func parseGitHubRepository(from remoteURL: String) -> String? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)

        if let scpPrefix = trimmed.range(of: "git@github.com:", options: .caseInsensitive) {
            return normalizeGitHubRepositoryPath(String(trimmed[scpPrefix.upperBound...]))
        }

        guard let components = URLComponents(string: trimmed),
              let host = components.host?.lowercased(),
              host == "github.com" || host == "www.github.com" else {
            return nil
        }

        return normalizeGitHubRepositoryPath(components.path)
    }

    static func normalizeGitHubRepositoryPath(_ path: String) -> String? {
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

private enum SidebarViewModelError: LocalizedError {
    case projectMissing
    case threadMissing
    case threadMissingParentProject
    case threadMissingDeletionMetadata

    var errorDescription: String? {
        switch self {
        case .projectMissing:
            return "Project no longer exists"
        case .threadMissing:
            return "Thread no longer exists"
        case .threadMissingParentProject:
            return "Thread is missing its parent project"
        case .threadMissingDeletionMetadata:
            return "Thread is missing worktree cleanup metadata needed for deletion"
        }
    }
}

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class SidebarViewModel {
    private let agentsManager: any AgentsManager
    private let modelContext: ModelContext
    private let shell: ShellRunner
    private let gitHubCLI: GitHubCLIService
    private let worktreeManager: WorktreeManager
    private let settingsService: SettingsService
    private let notificationManager: any NotificationManager
    private var statusObserver: NSObjectProtocol?

    private(set) var sidebarError: String?
    private(set) var statusVersion = 0

    init(
        agentsManager: any AgentsManager,
        modelContext: ModelContext,
        shell: ShellRunner,
        gitHubCLI: GitHubCLIService,
        worktreeManager: WorktreeManager,
        settingsService: SettingsService,
        notificationManager: any NotificationManager
    ) {
        self.agentsManager = agentsManager
        self.modelContext = modelContext
        self.shell = shell
        self.gitHubCLI = gitHubCLI
        self.worktreeManager = worktreeManager
        self.settingsService = settingsService
        self.notificationManager = notificationManager

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
        let projectDetails = try await resolveProjectDetails(for: path)

        // Load the shared repo config once during import so later settings/worktree flows
        // reuse the same parse path. Invalid JSON intentionally degrades to defaults.
        _ = await AlvearyProjectConfig(projectPath: projectDetails.path)

        let project = Project(
            path: projectDetails.path,
            name: URL(fileURLWithPath: projectDetails.path).lastPathComponent,
            gitRemote: projectDetails.remoteURL,
            remoteName: projectDetails.remoteName,
            gitBranch: projectDetails.gitBranch,
            baseRef: projectDetails.baseRef,
            githubRepository: projectDetails.githubRepository,
            githubConnected: projectDetails.githubConnected
        )
        modelContext.insert(project)
        try modelContext.save()
        return project
    }

    var deleteKeyAction: ThreadDeleteKeyAction {
        settingsService.current.deleteKeyAction
    }

    func createThread(project: Project, provider: String, permissionMode: String) async throws -> AgentThread {
        let dbProject = try requireProject(project)
        let defaultModel = settingsService.current.defaultModel
        let threadModel: String? = (defaultModel != AppSettings.defaultModelValue &&
            AppSettings.supportedModels.contains(defaultModel)) ? defaultModel : nil
        let thread = AgentThread(
            name: "New thread",
            permissionMode: permissionMode,
            effort: seedEffortLevel(forModel: threadModel),
            model: threadModel,
            useWorktree: settingsService.current.createWorktreeByDefault && dbProject.isGitRepository,
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

    // Thread seed = user's explicit Settings choice when valid for this model;
    // otherwise the per-model preferred default (Opus 4.7 → `xhigh`). "Explicit"
    // means the stored value differs from the universal `defaultEffortLevel`,
    // so a fresh install on Opus lands on `xhigh` rather than dragging
    // `medium` across from the unchanged Settings field.
    private func seedEffortLevel(forModel model: String?) -> String {
        let userEffort = settingsService.current.effort
        if userEffort != AppSettings.defaultEffortLevel,
           AppSettings.effortLevel(userEffort, isSupportedByModel: model) {
            return userEffort
        }
        return AppSettings.defaultEffortLevel(forModel: model)
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
        notificationManager.forgetConversations(in: [dbThread])
        dbThread.archivedAt = Date()
        try modelContext.save()
    }

    func restoreThread(_ thread: AgentThread) throws {
        let dbThread = try requireThread(thread)
        dbThread.prepareForRestore()
        try modelContext.save()
        notificationManager.refreshBadgeCount()
    }

    func deleteThread(_ thread: AgentThread) async throws {
        let dbThread = try requireThread(thread)
        guard let projectPath = dbThread.project?.path else {
            throw SidebarViewModelError.threadMissingParentProject
        }

        try await cleanupThreadResources(dbThread, projectPath: projectPath)

        notificationManager.forgetConversations(in: [dbThread])

        modelContext.delete(dbThread)
        try modelContext.save()
    }

    func deleteProject(_ project: Project) async throws {
        let dbProject = try requireProject(project)
        let threads = Array(dbProject.threads)
        let projectDirectoryExists = directoryExists(at: dbProject.path)

        for thread in threads {
            try await cleanupThreadResources(
                thread,
                projectPath: dbProject.path,
                skipGitCleanupWhenProjectMissing: !projectDirectoryExists
            )
        }

        try await worktreeManager.removeAll(projectPath: dbProject.path)

        notificationManager.forgetConversations(in: threads)

        modelContext.delete(dbProject)
        try modelContext.save()
    }

    func cleanupThreadResources(
        _ thread: AgentThread,
        projectPath: String,
        skipGitCleanupWhenProjectMissing: Bool = false
    ) async throws {
        try await quiesceThreadConversations(thread)

        if skipGitCleanupWhenProjectMissing, !directoryExists(at: projectPath) {
            return
        }

        for pendingCleanupBranch in thread.pendingCleanupBranches
        where pendingCleanupBranch != thread.branch {
            try await worktreeManager.deleteBranch(
                projectPath: projectPath,
                branch: pendingCleanupBranch
            )
        }

        let requiresCompletedWorktreeCleanup = thread.useWorktree && thread.hasCompletedInitialSetup
        if requiresCompletedWorktreeCleanup {
            guard let worktreePath = thread.worktreePath,
                  let branch = thread.branch else {
                throw SidebarViewModelError.threadMissingDeletionMetadata
            }
            try await worktreeManager.remove(
                projectPath: projectPath,
                worktreePath: worktreePath,
                branch: branch
            )
        } else if let worktreePath = thread.worktreePath {
            try await worktreeManager.remove(
                projectPath: projectPath,
                worktreePath: worktreePath,
                branch: thread.branch
            )
        } else if thread.branch != nil {
            throw SidebarViewModelError.threadMissingDeletionMetadata
        }
    }

    func threadStatus(for thread: AgentThread) -> ThreadStatus {
        thread.displayStatus { agentsManager.status(for: $0.id) }
    }
}

extension SidebarViewModel {
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

    func quiesceConversation(_ conversationId: String) async throws {
        try await agentsManager.destroyRuntime(conversationId: conversationId)
    }

    func quiesceThreadConversations(_ thread: AgentThread) async throws {
        let conversationIds = thread.conversations.map(\.id)
        var firstError: Error?

        for conversationId in conversationIds {
            do {
                try await quiesceConversation(conversationId)
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

    func directoryExists(at path: String) -> Bool {
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(
            atPath: path,
            isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue
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

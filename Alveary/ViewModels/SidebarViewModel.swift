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

    var defaultThreadCleanupAction: ThreadCleanupAction {
        settingsService.current.defaultThreadCleanupAction
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
        let snapshot = try makeThreadArchiveSnapshot(thread)
        await beginConversationTeardowns(snapshot.conversationIDs)
        notificationManager.forgetConversations(withIDs: snapshot.conversationIDs)
        guard let dbThread = modelContext.resolveThread(id: snapshot.threadID) else {
            do { try await awaitConversationTeardowns(snapshot.conversationIDs) } catch { throw SidebarViewModelError.archiveCleanupFailed(error) }
            return
        }
        dbThread.archivedAt = Date()
        try modelContext.save()
        do { try await awaitConversationTeardowns(snapshot.conversationIDs) } catch { throw SidebarViewModelError.archiveCleanupFailed(error) }
    }

    func restoreThread(_ thread: AgentThread) throws {
        let dbThread = try requireThread(thread)
        dbThread.prepareForRestore()
        try modelContext.save()
        notificationManager.refreshBadgeCount()
    }

    func deleteThread(_ thread: AgentThread) async throws {
        let snapshot = try makeThreadCleanupSnapshot(thread)
        await beginConversationTeardowns(snapshot.conversationIDs)
        notificationManager.forgetConversations(withIDs: snapshot.conversationIDs)
        guard let dbThread = modelContext.resolveThread(id: snapshot.threadID) else {
            do { try await cleanupThread(snapshot) } catch { throw SidebarViewModelError.threadDeleteCleanupFailed(error) }
            return
        }
        modelContext.delete(dbThread)
        try modelContext.save()

        do { try await cleanupThread(snapshot) } catch { throw SidebarViewModelError.threadDeleteCleanupFailed(error) }
    }

    func deleteProject(_ project: Project) async throws {
        let snapshot = try makeProjectDeletionSnapshot(project)
        let projectDirectoryExists = directoryExists(at: snapshot.projectPath)

        await beginConversationTeardowns(snapshot.conversationIDs)
        notificationManager.forgetConversations(withIDs: snapshot.conversationIDs)

        guard let dbProject = modelContext.resolveProject(id: snapshot.projectID) else {
            do {
                try await cleanupProjectResources(snapshot, projectDirectoryExists: projectDirectoryExists)
            } catch {
                throw SidebarViewModelError.projectDeleteCleanupFailed(error)
            }
            return
        }
        modelContext.delete(dbProject)
        try modelContext.save()

        do {
            try await cleanupProjectResources(snapshot, projectDirectoryExists: projectDirectoryExists)
        } catch {
            throw SidebarViewModelError.projectDeleteCleanupFailed(error)
        }
    }

    private func cleanupProjectResources(_ snapshot: ProjectDeletionSnapshot, projectDirectoryExists: Bool) async throws {
        try await awaitConversationTeardowns(snapshot.conversationIDs)

        for thread in snapshot.threadSnapshots {
            try await cleanupThread(
                thread,
                skipGitWhenProjectMissing: !projectDirectoryExists,
                waitForRuntime: false
            )
        }

        try await worktreeManager.removeAll(projectPath: snapshot.projectPath)
    }

    private func cleanupThread(_ snapshot: ThreadCleanupSnapshot, skipGitWhenProjectMissing: Bool = false, waitForRuntime: Bool = true) async throws {
        if waitForRuntime {
            try await awaitConversationTeardowns(snapshot.conversationIDs)
        }

        if skipGitWhenProjectMissing, !directoryExists(at: snapshot.projectPath) {
            return
        }

        for pendingCleanupBranch in snapshot.pendingCleanupBranches
        where pendingCleanupBranch != snapshot.branch {
            try await worktreeManager.deleteBranch(
                projectPath: snapshot.projectPath,
                branch: pendingCleanupBranch
            )
        }

        if snapshot.requiresCompletedWorktreeCleanup {
            guard let worktreePath = snapshot.worktreePath,
                  let branch = snapshot.branch else {
                throw SidebarViewModelError.threadMissingDeletionMetadata
            }
            try await worktreeManager.remove(
                projectPath: snapshot.projectPath,
                worktreePath: worktreePath,
                branch: branch
            )
        } else if let worktreePath = snapshot.worktreePath {
            try await worktreeManager.remove(
                projectPath: snapshot.projectPath,
                worktreePath: worktreePath,
                branch: snapshot.branch
            )
        } else if snapshot.branch != nil {
            throw SidebarViewModelError.threadMissingDeletionMetadata
        }
    }

    func threadStatus(for thread: AgentThread) -> ThreadStatus {
        thread.displayStatus { agentsManager.status(for: $0.id) }
    }

    func activeThreads(for project: Project) -> [AgentThread] {
        let projectPath = project.path
        let descriptor = FetchDescriptor<AgentThread>(
            predicate: #Predicate { thread in
                thread.archivedAt == nil && thread.project?.path == projectPath
            }
        )

        let threads = (try? modelContext.fetch(descriptor)) ?? []
        return threads.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
        guard let dbThread = modelContext.resolveThread(id: thread.persistentModelID) else {
            throw SidebarViewModelError.threadMissing
        }
        return dbThread
    }

    private func beginConversationTeardowns(_ conversationIDs: [String]) async {
        for conversationId in uniqueConversationIDs(conversationIDs) {
            await agentsManager.kill(conversationId: conversationId)
        }
    }

    private func awaitConversationTeardowns(_ conversationIDs: [String]) async throws {
        let conversationIDs = uniqueConversationIDs(conversationIDs)
        let agentsManager = agentsManager
        var errors = [Error?](repeating: nil, count: conversationIDs.count)

        await withTaskGroup(of: (Int, Error?).self) { group in
            for (index, conversationId) in conversationIDs.enumerated() {
                group.addTask {
                    do {
                        try await agentsManager.destroyRuntime(conversationId: conversationId)
                        return (index, nil)
                    } catch { return (index, error) }
                }
            }

            for await (index, error) in group {
                errors[index] = error
            }
        }

        if let firstError = errors.compactMap({ $0 }).first {
            throw firstError
        }
    }

    private func uniqueConversationIDs(_ conversationIDs: [String]) -> [String] {
        var seen = Set<String>()
        return conversationIDs.filter { seen.insert($0).inserted }
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

    private func makeThreadArchiveSnapshot(_ thread: AgentThread) throws -> ThreadArchiveSnapshot {
        let dbThread = try requireThread(thread)
        let threadID = dbThread.persistentModelID
        return ThreadArchiveSnapshot(
            threadID: threadID,
            conversationIDs: liveConversationIDs(for: threadID)
        )
    }

    private func makeThreadCleanupSnapshot(_ thread: AgentThread) throws -> ThreadCleanupSnapshot {
        let dbThread = try requireThread(thread)
        return try makeThreadCleanupSnapshot(from: dbThread)
    }

    private func makeThreadCleanupSnapshot(from thread: AgentThread) throws -> ThreadCleanupSnapshot {
        guard let projectPath = thread.project?.path else {
            throw SidebarViewModelError.threadMissingParentProject
        }

        let threadID = thread.persistentModelID
        return ThreadCleanupSnapshot(
            threadID: threadID,
            projectPath: projectPath,
            conversationIDs: liveConversationIDs(for: threadID),
            pendingCleanupBranches: thread.pendingCleanupBranches,
            branch: thread.branch,
            worktreePath: thread.worktreePath,
            requiresCompletedWorktreeCleanup: thread.useWorktree && thread.hasCompletedInitialSetup
        )
    }

    private func makeProjectDeletionSnapshot(_ project: Project) throws -> ProjectDeletionSnapshot {
        let dbProject = try requireProject(project)
        let projectPath = dbProject.path
        let threadSnapshots = try liveThreads(forProjectPath: projectPath).map(makeThreadCleanupSnapshot(from:))
        return ProjectDeletionSnapshot(
            projectID: dbProject.persistentModelID,
            projectPath: projectPath,
            conversationIDs: threadSnapshots.flatMap(\.conversationIDs),
            threadSnapshots: threadSnapshots
        )
    }

    private func liveThreads(forProjectPath projectPath: String) -> [AgentThread] {
        let descriptor = FetchDescriptor<AgentThread>(
            predicate: #Predicate { thread in
                thread.project?.path == projectPath
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func liveConversationIDs(for threadID: PersistentIdentifier) -> [String] {
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { conversation in
                conversation.thread?.persistentModelID == threadID
            }
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).map(\.id)
    }
}

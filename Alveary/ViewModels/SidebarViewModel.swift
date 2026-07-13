import AgentCLIKit
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class SidebarViewModel {
    let agentsManager: any AgentsManager
    let modelContext: ModelContext
    let shell: ShellRunner
    private let gitHubCLI: GitHubCLIService
    let worktreeManager: WorktreeManager
    let settingsService: SettingsService
    let providerDiscovery: (any AgentCLIKit.AgentProviderDiscoveryService)?
    let providerSessionActionService: any ProviderSessionActionService
    let attachmentStore: any ConversationAttachmentStore
    let taskWorkspaceOwnershipService: any TaskWorkspaceOwnershipService
    private let invalidateConversationController: @MainActor (String) -> Void
    let saveDraftProjectMove: @MainActor (ModelContext) throws -> Void
    let saveDeletionCommit: @MainActor (ModelContext) throws -> Void
    let saveThreadCreation: @MainActor (ModelContext) throws -> Void
    let savePendingSidebarChanges: @MainActor (ModelContext) throws -> Void
    let saveSidebarOrdering: @MainActor (ModelContext) throws -> Void
    private let presentUnexpectedError: @MainActor @Sendable (String) -> Void
    private let notificationManager: any NotificationManager
    private let threadActivityRecorder: any ThreadActivityRecording
    private var statusObserver: NSObjectProtocol?
    var threadActivityObserver: NSObjectProtocol?

    private(set) var sidebarError: String?
    var statusVersion = 0
    var threadOrderVersion = 0
    var activeForkSourceThreadIDs: Set<PersistentIdentifier> = []
    var draftCreationTasks: [AgentThreadMode: Task<PersistentIdentifier, Error>] = [:]
    var draftCreationTaskIDs: [AgentThreadMode: UUID] = [:]
    var pendingDraftProjectPaths: [AgentThreadMode: String] = [:]
    var cachedDraftThreadIDs: [AgentThreadMode: PersistentIdentifier] = [:]

    init(
        agentsManager: any AgentsManager,
        modelContext: ModelContext,
        shell: ShellRunner,
        gitHubCLI: GitHubCLIService,
        worktreeManager: WorktreeManager,
        settingsService: SettingsService,
        providerDiscovery: (any AgentCLIKit.AgentProviderDiscoveryService)? = nil,
        providerSessionActions: any ProviderSessionActionService = NoopProviderSessionActionService(),
        attachmentStore: any ConversationAttachmentStore = DefaultConversationAttachmentStore(),
        taskWorkspaceOwnershipService: any TaskWorkspaceOwnershipService = DefaultTaskWorkspaceOwnershipService(),
        invalidateConversationController: @escaping @MainActor (String) -> Void = { _ in },
        saveDraftProjectMove: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() },
        saveDeletionCommit: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() },
        saveThreadCreation: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() },
        savePendingSidebarChanges: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() },
        saveSidebarOrdering: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() },
        presentUnexpectedError: @escaping @MainActor @Sendable (String) -> Void = { _ in },
        notificationManager: any NotificationManager,
        threadActivityRecorder: any ThreadActivityRecording = NoopThreadActivityRecorder()
    ) {
        self.agentsManager = agentsManager
        self.modelContext = modelContext
        self.shell = shell
        self.gitHubCLI = gitHubCLI
        self.worktreeManager = worktreeManager
        self.settingsService = settingsService
        self.providerDiscovery = providerDiscovery
        self.providerSessionActionService = providerSessionActions
        self.attachmentStore = attachmentStore
        self.taskWorkspaceOwnershipService = taskWorkspaceOwnershipService
        self.invalidateConversationController = invalidateConversationController
        self.saveDraftProjectMove = saveDraftProjectMove
        self.saveDeletionCommit = saveDeletionCommit
        self.saveThreadCreation = saveThreadCreation
        self.savePendingSidebarChanges = savePendingSidebarChanges
        self.saveSidebarOrdering = saveSidebarOrdering
        self.presentUnexpectedError = presentUnexpectedError
        self.notificationManager = notificationManager
        self.threadActivityRecorder = threadActivityRecorder

        statusObserver = NotificationCenter.default.addObserver(
            forName: .agentStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.statusVersion += 1
            }
        }
        installThreadActivityObserver()
    }

    deinit {
        MainActor.assumeIsolated {
            if let statusObserver {
                NotificationCenter.default.removeObserver(statusObserver)
            }
            if let threadActivityObserver {
                NotificationCenter.default.removeObserver(threadActivityObserver)
            }
        }
    }

    var defaultThreadCleanupAction: ThreadCleanupAction {
        settingsService.current.defaultThreadCleanupAction
    }

    func presentSidebarError(_ error: Error) {
        sidebarError = error.localizedDescription
    }

    func dismissSidebarError() {
        sidebarError = nil
    }

    private func invalidateConversationControllers(_ conversationIDs: [String]) {
        for conversationID in conversationIDs {
            invalidateConversationController(conversationID)
        }
    }

    func archiveThread(_ thread: AgentThread) async throws {
        let dbThread = try requireThread(thread)
        guard !dbThread.isDraft else {
            throw SidebarViewModelError.threadMissing
        }
        let snapshot = try makeThreadArchiveSnapshot(dbThread)
        let providerSessionResolution = await providerSessionActionService.resolveSessions(matching: snapshot.providerSessionAction)
        try backfillProviderSessionBindings(from: providerSessionResolution.records)
        await beginConversationTeardowns(snapshot.conversationIDs)
        notificationManager.forgetConversations(withIDs: snapshot.conversationIDs)
        if let dbThread = modelContext.resolveThread(id: snapshot.threadID) {
            if modelContext.hasChanges {
                try modelContext.save()
            }
            do {
                dbThread.isPinned = false
                dbThread.pinnedSortOrder = nil
                dbThread.archivedAt = Date()
                _ = try normalizeSidebarOrderingForLifecycle()
                try modelContext.save()
            } catch {
                modelContext.rollback()
                throw error
            }
        }
        invalidateConversationControllers(snapshot.conversationIDs)

        let teardownError = await conversationTeardownError(snapshot.conversationIDs)
        let diagnostics = await providerSessionActionService.archiveSessions(providerSessionResolution)
        presentProviderSessionActionDiagnostics(diagnostics)
        if let teardownError {
            throw SidebarViewModelError.archiveCleanupFailed(teardownError)
        }
    }

    func restoreThread(_ thread: AgentThread) async throws {
        let snapshot = try makeThreadArchiveSnapshot(thread)
        let providerSessionResolution = await providerSessionActionService.resolveSessions(matching: snapshot.providerSessionAction)
        guard let dbThread = modelContext.resolveThread(id: snapshot.threadID),
              !dbThread.isDraft else {
            throw SidebarViewModelError.threadMissing
        }
        if modelContext.hasChanges {
            try modelContext.save()
        }
        do {
            dbThread.prepareForRestore()
            _ = try normalizeSidebarOrderingForLifecycle()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        notificationManager.refreshBadgeCount()
        let diagnostics = await providerSessionActionService.unarchiveSessions(providerSessionResolution)
        presentProviderSessionActionDiagnostics(diagnostics)
    }

    func deleteThread(_ thread: AgentThread) async throws {
        let snapshot = try makeThreadCleanupSnapshot(thread)
        // Keep this commit before the first suspension so a draft cannot be reused
        // or materialized while its teardown continues from the immutable snapshot.
        try commitThreadDeletion(snapshot)
        invalidateConversationControllers(snapshot.conversationIDs)
        notificationManager.forgetConversations(withIDs: snapshot.conversationIDs)

        let providerSessionResolution = await deleteProviderSessionResolution(for: snapshot.providerSessionAction)
        await beginConversationTeardowns(snapshot.conversationIDs)

        let teardownError = await conversationTeardownError(snapshot.conversationIDs)
        await removeConversationAttachmentDirectories(snapshot.conversationIDs)
        let diagnostics = await providerSessionActionService.deleteSessions(providerSessionResolution)
        presentProviderSessionActionDiagnostics(diagnostics)
        if let teardownError {
            throw SidebarViewModelError.threadDeleteCleanupFailed(teardownError)
        }

        do { try await cleanupThread(snapshot, waitForRuntime: false) } catch { throw SidebarViewModelError.threadDeleteCleanupFailed(error) }
    }

    func deleteProject(_ project: Project) async throws {
        let snapshot = try makeProjectDeletionSnapshot(project)
        let projectDirectoryExists = directoryExists(at: snapshot.projectPath)
        // Child drafts must disappear atomically before teardown yields to other UI work.
        try commitProjectDeletion(snapshot)
        invalidateConversationControllers(snapshot.conversationIDs)
        notificationManager.forgetConversations(withIDs: snapshot.conversationIDs)

        let providerSessionResolution = await deleteProviderSessionResolution(for: snapshot.threadSnapshots)
        await beginConversationTeardowns(snapshot.conversationIDs)

        let teardownError = await conversationTeardownError(snapshot.conversationIDs)
        await removeConversationAttachmentDirectories(snapshot.conversationIDs)
        let diagnostics = await providerSessionActionService.deleteSessions(providerSessionResolution)
        presentProviderSessionActionDiagnostics(diagnostics)
        if let teardownError {
            throw SidebarViewModelError.projectDeleteCleanupFailed(teardownError)
        }
        do {
            try await cleanupProjectResources(
                snapshot,
                projectDirectoryExists: projectDirectoryExists,
                waitForRuntime: false
            )
        } catch {
            throw SidebarViewModelError.projectDeleteCleanupFailed(error)
        }
    }

    private func cleanupProjectResources(
        _ snapshot: ProjectDeletionSnapshot,
        projectDirectoryExists: Bool,
        waitForRuntime: Bool = true
    ) async throws {
        if waitForRuntime {
            try await awaitConversationTeardowns(snapshot.conversationIDs)
        }

        for thread in snapshot.threadSnapshots {
            try await cleanupThread(
                thread,
                skipGitWhenProjectMissing: !projectDirectoryExists,
                waitForRuntime: false
            )
        }

    }

    private func cleanupThread(_ snapshot: ThreadCleanupSnapshot, skipGitWhenProjectMissing: Bool = false, waitForRuntime: Bool = true) async throws {
        if waitForRuntime {
            try await awaitConversationTeardowns(snapshot.conversationIDs)
        }

        if snapshot.mode == .task {
            try await cleanupTaskWorkspace(snapshot)
            return
        }

        guard let projectPath = snapshot.sourceProjectPath else {
            throw SidebarViewModelError.threadMissingParentProject
        }

        if skipGitWhenProjectMissing, !directoryExists(at: projectPath) {
            return
        }

        for pendingCleanupBranch in snapshot.pendingCleanupBranches
        where pendingCleanupBranch != snapshot.branch {
            try await worktreeManager.deleteBranch(
                projectPath: projectPath,
                branch: pendingCleanupBranch
            )
        }

        if snapshot.requiresCompletedWorktreeCleanup {
            guard let worktreePath = snapshot.worktreePath,
                  let branch = snapshot.branch else {
                throw SidebarViewModelError.threadMissingDeletionMetadata
            }
            try await worktreeManager.remove(
                projectPath: projectPath,
                worktreePath: worktreePath,
                branch: branch
            )
        } else if let worktreePath = snapshot.worktreePath {
            try await worktreeManager.remove(
                projectPath: projectPath,
                worktreePath: worktreePath,
                branch: snapshot.branch
            )
        } else if snapshot.branch != nil {
            throw SidebarViewModelError.threadMissingDeletionMetadata
        }
    }

    func threadStatus(for thread: AgentThread) -> ThreadStatus {
        if activeForkSourceThreadIDs.contains(thread.persistentModelID), thread.archivedAt == nil {
            return .busy
        }
        return thread.displayStatus { agentsManager.status(for: $0.id) }
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

    func presentProviderSessionActionDiagnostics(_ diagnostics: [ProviderSessionActionDiagnostic]) {
        for diagnostic in diagnostics {
            presentUnexpectedError(diagnostic.toastMessage)
        }
    }

    private func backfillProviderSessionBindings(from records: [AgentCLIKit.AgentSessionRecord]) throws {
        guard !records.isEmpty else {
            return
        }

        for record in records {
            guard let conversation = modelContext.resolveConversation(conversationID: record.conversationId.rawValue) else {
                continue
            }
            conversation.providerSessionId = record.providerSessionId.rawValue
            conversation.providerSessionProviderId = record.providerId.rawValue
            conversation.providerSessionWorkingDirectory = record.workingDirectory?.path
        }
        try modelContext.save()
    }

    private func conversationTeardownError(_ conversationIDs: [String]) async -> Error? {
        do {
            try await awaitConversationTeardowns(conversationIDs)
            return nil
        } catch {
            return error
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

}

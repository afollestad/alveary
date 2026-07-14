import Foundation
import SwiftData

struct ThreadArchiveSnapshot {
    let threadID: PersistentIdentifier
    let mode: AgentThreadMode
    let conversationIDs: [String]
    let providerSessionAction: ProviderSessionActionSnapshot
}

struct ThreadCleanupSnapshot {
    let threadID: PersistentIdentifier
    let mode: AgentThreadMode
    let sourceProjectPath: String?
    let taskWorkspace: TaskWorkspaceDescriptor?
    let scheduledTaskRunID: PersistentIdentifier?
    let pendingScheduledWorktreeCleanup: ScheduledWorktreeCleanupProvenance?
    let conversationIDs: [String]
    let providerSessionAction: ProviderSessionActionSnapshot
    let pendingCleanupBranches: [String]
    let branch: String?
    let worktreePath: String?
    let requiresCompletedWorktreeCleanup: Bool
}

struct ProjectDeletionSnapshot {
    let projectID: PersistentIdentifier
    let projectPath: String
    let scheduledTaskIDs: [String]
    let detachedTaskThreadIDs: [PersistentIdentifier]
    let conversationIDs: [String]
    let threadSnapshots: [ThreadCleanupSnapshot]
}

enum ThreadLifecyclePersistenceState {
    case active
    case archived
    case missing
}

enum SidebarViewModelError: LocalizedError {
    case projectMissing
    case threadMissing
    case threadMissingParentProject
    case threadMissingTaskWorkspace
    case threadMissingDeletionMetadata
    case scheduledTaskRunStillActive
    case threadForkUnavailable(String)
    case threadForkFailed(Error)
    case threadForkRollbackFailed(original: Error, cleanup: Error)
    case archiveCleanupFailed(Error)
    case threadDeletePreparationFailed(Error)
    case threadDeleteCleanupFailed(Error)
    case projectDeleteCleanupFailed(Error)
    case noReadyThreadDefaultProvider

    var errorDescription: String? {
        switch self {
        case .projectMissing:
            return "Project no longer exists"
        case .threadMissing:
            return "Thread no longer exists"
        case .threadMissingParentProject:
            return "Thread is missing its parent project"
        case .threadMissingTaskWorkspace:
            return "Task is missing its workspace metadata"
        case .threadMissingDeletionMetadata:
            return "Thread is missing worktree cleanup metadata needed for deletion"
        case .scheduledTaskRunStillActive:
            return "The scheduled Task is still stopping. Try again after its run finishes."
        case .threadForkUnavailable(let reason):
            return reason
        case .threadForkFailed(let error):
            return "Thread fork failed: \(error.localizedDescription)"
        case .threadForkRollbackFailed(let original, let cleanup):
            return "Thread fork failed: \(original.localizedDescription). Rollback cleanup also failed: \(cleanup.localizedDescription)"
        case .archiveCleanupFailed(let error):
            return "Thread was archived, but runtime cleanup failed: \(error.localizedDescription)"
        case .threadDeletePreparationFailed(let error):
            return "Thread was not deleted because its pending cleanup failed: \(error.localizedDescription)"
        case .threadDeleteCleanupFailed(let error):
            return "Thread was deleted, but cleanup failed: \(error.localizedDescription)"
        case .projectDeleteCleanupFailed(let error):
            return "Project was deleted, but cleanup failed: \(error.localizedDescription)"
        case .noReadyThreadDefaultProvider:
            return "No enabled provider is installed and ready for new threads"
        }
    }

    var isPostCommitCleanupFailure: Bool {
        switch self {
        case .archiveCleanupFailed, .threadDeleteCleanupFailed, .projectDeleteCleanupFailed:
            return true
        case .projectMissing, .threadMissing, .threadMissingParentProject, .threadMissingTaskWorkspace, .threadMissingDeletionMetadata,
             .scheduledTaskRunStillActive,
             .threadForkUnavailable, .threadForkFailed, .threadForkRollbackFailed,
             .threadDeletePreparationFailed, .noReadyThreadDefaultProvider:
            return false
        }
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

    func threadLifecyclePersistenceState(id: PersistentIdentifier) -> ThreadLifecyclePersistenceState {
        guard let thread = modelContext.resolveThread(id: id) else {
            return .missing
        }
        return thread.archivedAt == nil ? .active : .archived
    }

    func makeThreadArchiveSnapshot(_ thread: AgentThread) throws -> ThreadArchiveSnapshot {
        let dbThread = try requireThread(thread)
        let threadID = dbThread.persistentModelID
        return ThreadArchiveSnapshot(
            threadID: threadID,
            mode: dbThread.effectiveMode,
            conversationIDs: liveConversationIDs(for: threadID),
            providerSessionAction: providerSessionActionSnapshot(for: dbThread)
        )
    }

    func makeThreadCleanupSnapshot(_ thread: AgentThread) throws -> ThreadCleanupSnapshot {
        let dbThread = try requireThread(thread)
        return try makeThreadCleanupSnapshot(from: dbThread)
    }

    func makeThreadCleanupSnapshot(from thread: AgentThread) throws -> ThreadCleanupSnapshot {
        let cleanupMode = thread.effectiveMode
        let sourceProjectPath: String?
        let taskWorkspace: TaskWorkspaceDescriptor?
        let scheduledTaskRunID: PersistentIdentifier?
        let pendingScheduledWorktreeCleanup: ScheduledWorktreeCleanupProvenance?
        switch cleanupMode {
        case .project:
            guard let projectPath = thread.project?.path else {
                throw SidebarViewModelError.threadMissingParentProject
            }
            sourceProjectPath = projectPath
            taskWorkspace = nil
            scheduledTaskRunID = nil
            pendingScheduledWorktreeCleanup = nil
        case .task:
            let metadata = try taskThreadCleanupMetadata(thread)
            sourceProjectPath = metadata.sourceProjectPath
            taskWorkspace = metadata.workspace
            scheduledTaskRunID = metadata.runID
            pendingScheduledWorktreeCleanup = metadata.pendingWorktreeCleanup
        }

        let threadID = thread.persistentModelID
        return ThreadCleanupSnapshot(
            threadID: threadID,
            mode: cleanupMode,
            sourceProjectPath: sourceProjectPath,
            taskWorkspace: taskWorkspace,
            scheduledTaskRunID: scheduledTaskRunID,
            pendingScheduledWorktreeCleanup: pendingScheduledWorktreeCleanup,
            conversationIDs: liveConversationIDs(for: threadID),
            providerSessionAction: providerSessionActionSnapshot(for: thread),
            pendingCleanupBranches: thread.pendingCleanupBranches,
            branch: thread.branch,
            worktreePath: thread.worktreePath,
            requiresCompletedWorktreeCleanup: thread.useWorktree && thread.hasCompletedInitialSetup
        )
    }

    func makeProjectDeletionSnapshot(_ project: Project) throws -> ProjectDeletionSnapshot {
        let dbProject = try requireProject(project)
        let projectPath = dbProject.path
        let attachedThreads = liveThreads(forProjectPath: projectPath)
        let taskThreads = attachedThreads.filter {
            $0.effectiveMode == .task
        }
        let taskThreadIDs = Set(taskThreads.map(\.persistentModelID))
        let threadSnapshots = try attachedThreads
            .filter { !taskThreadIDs.contains($0.persistentModelID) }
            .map(makeThreadCleanupSnapshot(from:))
        return ProjectDeletionSnapshot(
            projectID: dbProject.persistentModelID,
            projectPath: projectPath,
            scheduledTaskIDs: dbProject.scheduledTasks.map(\.id),
            detachedTaskThreadIDs: taskThreads.map(\.persistentModelID),
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

    private func taskThreadCleanupMetadata(_ thread: AgentThread) throws -> TaskThreadCleanupMetadata {
        let run = thread.scheduledTaskRun
        let pendingCleanup = run?.pendingWorktreeCleanup
        if let workspace = persistedTaskWorkspaceDescriptor(thread) {
            guard run?.hasPendingWorktreeCleanupMetadata != true else {
                throw SidebarViewModelError.threadMissingDeletionMetadata
            }
            return TaskThreadCleanupMetadata(
                sourceProjectPath: workspace.sourceProjectPath,
                workspace: workspace,
                runID: run?.persistentModelID,
                pendingWorktreeCleanup: nil
            )
        }
        guard let run,
              ScheduledTaskRunStatus(rawValue: run.statusRawValue)?.isTerminal == true,
              thread.worktreePath == nil,
              thread.branch == nil,
              !thread.useWorktree,
              thread.pendingCleanupBranches.isEmpty else {
            throw SidebarViewModelError.threadMissingTaskWorkspace
        }
        if !run.hasPendingWorktreeCleanupMetadata,
           run.preparedWorkspaceOwnershipStrategy != nil {
            return try preparedScheduledRunCleanupMetadata(run)
        }
        guard
              run.preparedWorkspaceRoot == nil,
              run.preparedOwnershipStrategyRawValue == nil,
              run.preparedWorkspaceMarkerID == nil,
              !run.hasPendingWorktreeCleanupMetadata || pendingCleanup != nil else {
            throw SidebarViewModelError.threadMissingTaskWorkspace
        }
        return TaskThreadCleanupMetadata(
            sourceProjectPath: pendingCleanup?.sourceProjectPath,
            workspace: nil,
            runID: run.persistentModelID,
            pendingWorktreeCleanup: pendingCleanup
        )
    }

    private func persistedTaskWorkspaceDescriptor(_ thread: AgentThread) -> TaskWorkspaceDescriptor? {
        guard let primaryRoot = thread.taskPrimaryRoot,
              !primaryRoot.isEmpty,
              let ownershipStrategyRawValue = thread.taskWorkspaceOwnershipStrategyRawValue,
              let ownershipStrategy = TaskWorkspaceOwnershipStrategy(rawValue: ownershipStrategyRawValue) else {
            return nil
        }
        return TaskWorkspaceDescriptor(
            persistedPrimaryRoot: primaryRoot,
            persistedGrantedRoots: thread.taskGrantedRoots,
            ownershipStrategy: ownershipStrategy,
            ownershipMarkerID: thread.taskWorkspaceMarkerID,
            persistedSourceProjectPath: thread.taskSourceProjectPath
        )
    }

    private func preparedScheduledRunCleanupMetadata(
        _ run: ScheduledTaskRun
    ) throws -> TaskThreadCleanupMetadata {
        guard let root = canonicalCleanupPath(run.preparedWorkspaceRoot),
              let ownershipStrategy = run.preparedWorkspaceOwnershipStrategy,
              ownershipStrategy == expectedCleanupOwnershipStrategy(for: run) else {
            throw SidebarViewModelError.threadMissingDeletionMetadata
        }

        switch ownershipStrategy {
        case .projectLocal:
            guard run.preparedWorkspaceMarkerID == nil,
                  canonicalCleanupPath(run.projectPathSnapshot) == root else {
                throw SidebarViewModelError.threadMissingDeletionMetadata
            }
            return TaskThreadCleanupMetadata(
                sourceProjectPath: nil,
                workspace: nil,
                runID: run.persistentModelID,
                pendingWorktreeCleanup: nil
            )
        case .privateOwned, .projectWorktreeOwned:
            let sourceProjectPath = ownershipStrategy == .projectWorktreeOwned
                ? canonicalCleanupPath(run.projectPathSnapshot)
                : nil
            guard ownershipStrategy != .projectWorktreeOwned || sourceProjectPath != nil,
                  let markerID = cleanupMarkerID(
                      run.preparedWorkspaceMarkerID,
                      root: root,
                      ownershipStrategy: ownershipStrategy
                  ) else {
                throw SidebarViewModelError.threadMissingDeletionMetadata
            }
            let workspace = TaskWorkspaceDescriptor(
                persistedPrimaryRoot: root,
                persistedGrantedRoots: [],
                ownershipStrategy: ownershipStrategy,
                ownershipMarkerID: markerID,
                persistedSourceProjectPath: sourceProjectPath
            )
            return TaskThreadCleanupMetadata(
                sourceProjectPath: sourceProjectPath,
                workspace: workspace,
                runID: run.persistentModelID,
                pendingWorktreeCleanup: nil
            )
        }
    }

    func expectedCleanupOwnershipStrategy(
        for run: ScheduledTaskRun
    ) -> TaskWorkspaceOwnershipStrategy? {
        guard let workspaceKind = ScheduledTaskWorkspaceKind(rawValue: run.workspaceKindRawValueSnapshot),
              let workspaceStrategy = ScheduledTaskWorkspaceStrategy(rawValue: run.workspaceStrategyRawValueSnapshot) else {
            return nil
        }
        switch (workspaceKind, workspaceStrategy) {
        case (.privateWorkspace, _):
            return .privateOwned
        case (.project, .localCheckout):
            return .projectLocal
        case (.project, .worktree):
            return .projectWorktreeOwned
        }
    }

    func canonicalCleanupPath(_ path: String?) -> String? {
        guard let path,
              NSString(string: path).isAbsolutePath,
              CanonicalPath.normalize(path) == path else {
            return nil
        }
        return path
    }

    func cleanupMarkerID(
        _ markerID: String?,
        root: String,
        ownershipStrategy: TaskWorkspaceOwnershipStrategy
    ) -> String? {
        if let markerID,
           UUID(uuidString: markerID) != nil {
            return markerID.lowercased()
        }
        guard ownershipStrategy == .privateOwned else {
            return nil
        }
        let rootMarkerID = URL(fileURLWithPath: root, isDirectory: true).lastPathComponent
        guard UUID(uuidString: rootMarkerID) != nil else {
            return nil
        }
        return rootMarkerID.lowercased()
    }

    private func liveConversationIDs(for threadID: PersistentIdentifier) -> [String] {
        liveConversations(for: threadID).map(\.id)
    }

    private func providerSessionActionSnapshot(for thread: AgentThread) -> ProviderSessionActionSnapshot {
        let threadID = thread.persistentModelID
        let workingDirectory = thread.primaryWorkingDirectory.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        return ProviderSessionActionSnapshot(
            conversations: liveConversations(for: threadID).map {
                ProviderSessionConversationSnapshot(
                    conversationID: $0.id,
                    providerID: $0.provider,
                    providerSessionID: $0.providerSessionId,
                    providerSessionProviderID: $0.providerSessionProviderId,
                    providerSessionWorkingDirectory: $0.providerSessionWorkingDirectory
                )
            },
            workingDirectory: workingDirectory
        )
    }

    private func liveConversations(for threadID: PersistentIdentifier) -> [Conversation] {
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { conversation in
                conversation.thread?.persistentModelID == threadID
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}

private struct TaskThreadCleanupMetadata {
    let sourceProjectPath: String?
    let workspace: TaskWorkspaceDescriptor?
    let runID: PersistentIdentifier?
    let pendingWorktreeCleanup: ScheduledWorktreeCleanupProvenance?
}

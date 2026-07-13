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
    let detachedTaskThreadIDs: [PersistentIdentifier]
    let conversationIDs: [String]
    let threadSnapshots: [ThreadCleanupSnapshot]
}

enum SidebarViewModelError: LocalizedError {
    case projectMissing
    case threadMissing
    case threadMissingParentProject
    case threadMissingTaskWorkspace
    case threadMissingDeletionMetadata
    case threadForkUnavailable(String)
    case threadForkFailed(Error)
    case threadForkRollbackFailed(original: Error, cleanup: Error)
    case archiveCleanupFailed(Error)
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
        case .threadForkUnavailable(let reason):
            return reason
        case .threadForkFailed(let error):
            return "Thread fork failed: \(error.localizedDescription)"
        case .threadForkRollbackFailed(let original, let cleanup):
            return "Thread fork failed: \(original.localizedDescription). Rollback cleanup also failed: \(cleanup.localizedDescription)"
        case .archiveCleanupFailed(let error):
            return "Thread was archived, but runtime cleanup failed: \(error.localizedDescription)"
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
             .threadForkUnavailable, .threadForkFailed, .threadForkRollbackFailed, .noReadyThreadDefaultProvider:
            return false
        }
    }
}

extension SidebarViewModel {
    func makeThreadArchiveSnapshot(_ thread: AgentThread) throws -> ThreadArchiveSnapshot {
        let dbThread = try requireThread(thread)
        let threadID = dbThread.persistentModelID
        return ThreadArchiveSnapshot(
            threadID: threadID,
            mode: dbThread.mode,
            conversationIDs: liveConversationIDs(for: threadID),
            providerSessionAction: providerSessionActionSnapshot(for: dbThread)
        )
    }

    func makeThreadCleanupSnapshot(_ thread: AgentThread) throws -> ThreadCleanupSnapshot {
        let dbThread = try requireThread(thread)
        return try makeThreadCleanupSnapshot(from: dbThread)
    }

    func makeThreadCleanupSnapshot(from thread: AgentThread) throws -> ThreadCleanupSnapshot {
        let sourceProjectPath: String?
        let taskWorkspace: TaskWorkspaceDescriptor?
        switch thread.mode {
        case .project:
            guard let projectPath = thread.project?.path else {
                throw SidebarViewModelError.threadMissingParentProject
            }
            sourceProjectPath = projectPath
            taskWorkspace = nil
        case .task:
            guard let workspace = thread.taskWorkspaceDescriptor else {
                throw SidebarViewModelError.threadMissingTaskWorkspace
            }
            sourceProjectPath = thread.sourceProjectCleanupPath
            taskWorkspace = workspace
        }

        let threadID = thread.persistentModelID
        return ThreadCleanupSnapshot(
            threadID: threadID,
            mode: thread.mode,
            sourceProjectPath: sourceProjectPath,
            taskWorkspace: taskWorkspace,
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
        let threadSnapshots = try attachedThreads
            .filter { $0.mode == .project }
            .map(makeThreadCleanupSnapshot(from:))
        return ProjectDeletionSnapshot(
            projectID: dbProject.persistentModelID,
            projectPath: projectPath,
            detachedTaskThreadIDs: attachedThreads
                .filter { $0.mode == .task }
                .map(\.persistentModelID),
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

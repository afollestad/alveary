import Foundation
import SwiftData

struct ThreadArchiveSnapshot {
    let threadID: PersistentIdentifier
    let conversationIDs: [String]
    let providerSessionAction: ProviderSessionActionSnapshot
}

struct ThreadCleanupSnapshot {
    let threadID: PersistentIdentifier
    let projectPath: String
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
    let conversationIDs: [String]
    let threadSnapshots: [ThreadCleanupSnapshot]
}

enum SidebarViewModelError: LocalizedError {
    case projectMissing
    case threadMissing
    case threadMissingParentProject
    case threadMissingDeletionMetadata
    case archiveCleanupFailed(Error)
    case threadDeleteCleanupFailed(Error)
    case projectDeleteCleanupFailed(Error)

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
        case .archiveCleanupFailed(let error):
            return "Thread was archived, but runtime cleanup failed: \(error.localizedDescription)"
        case .threadDeleteCleanupFailed(let error):
            return "Thread was deleted, but cleanup failed: \(error.localizedDescription)"
        case .projectDeleteCleanupFailed(let error):
            return "Project was deleted, but cleanup failed: \(error.localizedDescription)"
        }
    }

    var isPostCommitCleanupFailure: Bool {
        switch self {
        case .archiveCleanupFailed, .threadDeleteCleanupFailed, .projectDeleteCleanupFailed:
            return true
        case .projectMissing, .threadMissing, .threadMissingParentProject, .threadMissingDeletionMetadata:
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
            conversationIDs: liveConversationIDs(for: threadID),
            providerSessionAction: providerSessionActionSnapshot(for: dbThread)
        )
    }

    func makeThreadCleanupSnapshot(_ thread: AgentThread) throws -> ThreadCleanupSnapshot {
        let dbThread = try requireThread(thread)
        return try makeThreadCleanupSnapshot(from: dbThread)
    }

    func makeThreadCleanupSnapshot(from thread: AgentThread) throws -> ThreadCleanupSnapshot {
        guard let projectPath = thread.project?.path else {
            throw SidebarViewModelError.threadMissingParentProject
        }

        let threadID = thread.persistentModelID
        return ThreadCleanupSnapshot(
            threadID: threadID,
            projectPath: projectPath,
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
        liveConversations(for: threadID).map(\.id)
    }

    private func providerSessionActionSnapshot(for thread: AgentThread) -> ProviderSessionActionSnapshot {
        let threadID = thread.persistentModelID
        let workingDirectory = (thread.worktreePath ?? thread.project?.path).map {
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

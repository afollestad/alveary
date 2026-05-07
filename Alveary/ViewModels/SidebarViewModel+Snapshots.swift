import Foundation
import SwiftData

struct ThreadArchiveSnapshot {
    let threadID: PersistentIdentifier
    let conversationIDs: [String]
}

struct ThreadCleanupSnapshot {
    let threadID: PersistentIdentifier
    let projectPath: String
    let conversationIDs: [String]
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

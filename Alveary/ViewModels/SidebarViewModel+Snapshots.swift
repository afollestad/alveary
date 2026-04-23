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

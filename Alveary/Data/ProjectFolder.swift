import Foundation
import SwiftData

/// Membership belongs to a project; the referenced directory does not. Deleting this row never deletes files.
@Model
final class ProjectFolder {
    @Attribute(.unique) var id: String
    var path: String
    var sortOrder: Int
    var gitRemote: String?
    var remoteName: String?
    var gitBranch: String?
    var baseRef: String?
    var githubRepository: String?
    var githubConnected: Bool
    var project: Project?

    init(id: String = UUID().uuidString, snapshot: SourceFolderSnapshot, sortOrder: Int = 0) {
        self.id = id
        self.path = snapshot.path
        self.sortOrder = sortOrder
        self.gitRemote = snapshot.gitRemote
        self.remoteName = snapshot.remoteName
        self.gitBranch = snapshot.gitBranch
        self.baseRef = snapshot.baseRef
        self.githubRepository = snapshot.githubRepository
        self.githubConnected = snapshot.githubConnected
    }

    var snapshot: SourceFolderSnapshot {
        SourceFolderSnapshot(
            path: path, gitRemote: gitRemote, remoteName: remoteName, gitBranch: gitBranch,
            baseRef: baseRef, githubRepository: githubRepository, githubConnected: githubConnected
        )
    }
}

/// A value snapshot can cross suspensions and outlive project edits or deletion. Paths are already canonical;
/// rehydration deliberately does not follow symlinks or require the directory to still exist.
struct SourceFolderSnapshot: Codable, Hashable, Sendable, Identifiable {
    let path: String
    var gitRemote: String?
    var remoteName: String?
    var gitBranch: String?
    var baseRef: String?
    var githubRepository: String?
    var githubConnected: Bool = false
    /// Owned worktree provenance can establish Git even when the source's branch/remote metadata is unavailable.
    var gitRepositoryDetected: Bool?

    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
    var isGitRepository: Bool {
        gitRepositoryDetected == true || gitBranch != nil || baseRef != nil || remoteName != nil || gitRemote != nil || githubRepository != nil
    }
}

import Foundation

struct WorktreeInfo: Identifiable, Sendable, Equatable {
    var id: String { path }

    let path: String
    let branch: String
}

protocol WorktreeManager: Actor {
    func create(
        projectPath: String,
        threadName: String,
        baseRef: String?,
        remoteName: String?
    ) async throws -> WorktreeInfo

    func createFromBranch(
        projectPath: String,
        threadName: String,
        branch: String,
        remoteName: String?
    ) async throws -> WorktreeInfo

    func remove(
        projectPath: String,
        worktreePath: String,
        branch: String?
    ) async throws

    func deleteBranch(projectPath: String, branch: String) async throws
    func list(projectPath: String) async throws -> [WorktreeInfo]
}

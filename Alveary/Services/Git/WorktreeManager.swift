import Foundation

struct WorktreeInfo: Identifiable, Sendable, Equatable {
    var id: String { path }

    let path: String
    let branch: String
    let headOID: String?

    init(path: String, branch: String, headOID: String? = nil) {
        self.path = path
        self.branch = branch
        self.headOID = headOID
    }
}

struct IdentityValidatedWorktreeInfo: Sendable, Equatable {
    let info: WorktreeInfo
    let sourceProjectIdentity: TaskWorkspaceFileSystemIdentity
    let worktreeIdentity: TaskWorkspaceFileSystemIdentity
}

struct FailedWorktreeCreationCleanup: Sendable, Equatable {
    let sourceProjectPath: String
    let worktreePath: String
    let branch: String
    let sourceProjectIdentity: TaskWorkspaceFileSystemIdentity
    let worktreeIdentity: TaskWorkspaceFileSystemIdentity?
    let branchIsOwned: Bool
    let branchOID: String?

    init(
        sourceProjectPath: String,
        worktreePath: String,
        branch: String,
        sourceProjectIdentity: TaskWorkspaceFileSystemIdentity,
        worktreeIdentity: TaskWorkspaceFileSystemIdentity?,
        branchIsOwned: Bool = true,
        branchOID: String? = nil
    ) {
        self.sourceProjectPath = sourceProjectPath
        self.worktreePath = worktreePath
        self.branch = branch
        self.sourceProjectIdentity = sourceProjectIdentity
        self.worktreeIdentity = worktreeIdentity
        self.branchIsOwned = branchIsOwned && branchOID != nil
        self.branchOID = self.branchIsOwned ? branchOID : nil
    }
}

typealias WorktreeCreationProvenanceRecorder = @MainActor @Sendable (
    _ cleanup: FailedWorktreeCreationCleanup
) throws -> Void

struct WorktreeCreationProvenanceContext: Sendable {
    let expectedProjectIdentity: TaskWorkspaceFileSystemIdentity
    let recorder: WorktreeCreationProvenanceRecorder
}

struct WorktreeCreationRollbackError: LocalizedError, Sendable, Equatable {
    let creationErrorDescription: String
    let cleanup: FailedWorktreeCreationCleanup

    var errorDescription: String? {
        "Worktree creation failed (\(creationErrorDescription)), and identity-safe rollback could not finish."
    }
}

enum WorktreeSourceValidationError: LocalizedError, Equatable, Sendable {
    case sourceProjectChanged(String)
    case ownedWorktreeChanged(String)

    var errorDescription: String? {
        switch self {
        case .sourceProjectChanged(let path):
            "Refusing Git cleanup because the source Project directory changed: \(path)"
        case .ownedWorktreeChanged(let path):
            "Refusing Git cleanup because the owned worktree directory changed: \(path)"
        }
    }
}

struct RetryableWorktreeBranchDeletionError: LocalizedError {
    let underlying: Error

    var errorDescription: String? {
        underlying.localizedDescription
    }
}

protocol WorktreeManager: Actor {
    func validateCreation(
        projectPath: String,
        baseRef: String?,
        remoteName: String?
    ) async throws

    func validateCreation(
        projectPath: String,
        baseRef: String?,
        remoteName: String?,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity
    ) async throws

    func create(
        projectPath: String,
        threadName: String,
        baseRef: String?,
        remoteName: String?
    ) async throws -> WorktreeInfo

    func create(
        projectPath: String,
        threadName: String,
        baseRef: String?,
        remoteName: String?,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity
    ) async throws -> IdentityValidatedWorktreeInfo

    func create(
        projectPath: String,
        threadName: String,
        baseRef: String?,
        remoteName: String?,
        provenanceContext: WorktreeCreationProvenanceContext
    ) async throws -> IdentityValidatedWorktreeInfo

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

    func remove(
        projectPath: String,
        worktreePath: String,
        branch: String?,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity,
        expectedWorktreeIdentity: TaskWorkspaceFileSystemIdentity?
    ) async throws

    func prepareForkContext(sourcePath: String, worktreePath: String) async throws
    func removeAll(projectPath: String) async throws
    func deleteBranch(projectPath: String, branch: String, expectedOID: String) async throws
    func deleteBranch(
        projectPath: String,
        branch: String,
        expectedOID: String,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity
    ) async throws
    func list(projectPath: String) async throws -> [WorktreeInfo]
}

extension WorktreeManager {
    func prepareForkContext(sourcePath: String, worktreePath: String) async throws {}

    func create(
        projectPath: String,
        threadName: String,
        baseRef: String?,
        remoteName: String?,
        provenanceContext: WorktreeCreationProvenanceContext
    ) async throws -> IdentityValidatedWorktreeInfo {
        let created = try await create(
            projectPath: projectPath,
            threadName: threadName,
            baseRef: baseRef,
            remoteName: remoteName,
            expectedProjectIdentity: provenanceContext.expectedProjectIdentity
        )
        try await provenanceContext.recorder(
            FailedWorktreeCreationCleanup(
                sourceProjectPath: projectPath,
                worktreePath: created.info.path,
                branch: created.info.branch,
                sourceProjectIdentity: created.sourceProjectIdentity,
                worktreeIdentity: created.worktreeIdentity,
                branchIsOwned: created.info.headOID != nil,
                branchOID: created.info.headOID
            )
        )
        return created
    }
}

import Foundation

struct WorktreeCreationRollbackState {
    let worktreeIdentity: TaskWorkspaceFileSystemIdentity?
    let branchIsOwned: Bool
    let branchOID: String?
    let provenanceContext: WorktreeCreationProvenanceContext?
}

extension DefaultWorktreeManager {
    func throwCreationFailure(
        _ error: Error,
        prepared: PreparedWorktreeCreation,
        rollback: WorktreeCreationRollbackState
    ) async throws -> Never {
        let rollbackBranchOID = await refreshRollbackBranchOID(
            prepared,
            worktreeIdentity: rollback.worktreeIdentity,
            branchIsOwned: rollback.branchIsOwned,
            branchOID: rollback.branchOID,
            provenanceContext: rollback.provenanceContext
        )
        let cleanupFailed = await detachedCleanupAfterFailedCreate(
            projectPath: prepared.projectPath,
            worktreePath: prepared.target.path,
            rollbackBranch: rollback.branchIsOwned ? prepared.target.branch : nil,
            rollbackBranchOID: rollbackBranchOID,
            identityValidation: WorktreeCreationIdentityValidation(
                project: prepared.expectedProjectIdentity,
                worktree: rollback.worktreeIdentity
            )
        )
        let creationDescription = (error as? WorktreeSetupFailure).map {
            "Setup script failed: \($0.message)"
        } ?? error.localizedDescription
        if cleanupFailed, let expectedProjectIdentity = prepared.expectedProjectIdentity {
            throw WorktreeCreationRollbackError(
                creationErrorDescription: creationDescription,
                cleanup: FailedWorktreeCreationCleanup(
                    sourceProjectPath: prepared.projectPath,
                    worktreePath: prepared.target.path,
                    branch: prepared.target.branch,
                    sourceProjectIdentity: expectedProjectIdentity,
                    worktreeIdentity: rollback.worktreeIdentity,
                    branchIsOwned: rollback.branchIsOwned,
                    branchOID: rollbackBranchOID
                )
            )
        }
        if error is WorktreeSetupFailure {
            if cleanupFailed {
                throw GitError.commandFailed(
                    "\(creationDescription). Cleanup also failed for worktree \(prepared.target.path)."
                )
            }
            throw GitError.commandFailed(creationDescription)
        }
        throw error
    }

    func throwCreateFromBranchFailure(
        _ error: Error,
        projectPath: String,
        worktreePath: String
    ) async throws -> Never {
        let cleanupFailed = await detachedCleanupAfterFailedCreate(
            projectPath: projectPath,
            worktreePath: worktreePath,
            rollbackBranch: nil,
            rollbackBranchOID: nil,
            identityValidation: .unchecked
        )
        guard let setupFailure = error as? WorktreeSetupFailure else {
            throw error
        }
        if cleanupFailed {
            throw GitError.commandFailed(
                "Setup script failed: \(setupFailure.message). Cleanup also failed for worktree \(worktreePath)."
            )
        }
        throw GitError.commandFailed("Setup script failed: \(setupFailure.message)")
    }
}

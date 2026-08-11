import Foundation

extension DefaultWorktreeManager {
    func remove(projectPath: String, worktreePath: String, branch: String?) async throws {
        try await removeValidated(
            projectPath: projectPath,
            worktreePath: worktreePath,
            branch: branch,
            identityValidation: .unchecked
        )
    }

    func remove(
        projectPath: String,
        worktreePath: String,
        branch: String?,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity,
        expectedWorktreeIdentity: TaskWorkspaceFileSystemIdentity?
    ) async throws {
        try await removeValidated(
            projectPath: projectPath,
            worktreePath: worktreePath,
            branch: branch,
            identityValidation: WorktreeRemovalIdentityValidation(
                project: expectedProjectIdentity,
                worktree: expectedWorktreeIdentity,
                validatesWorktree: true
            )
        )
    }

    private func removeValidated(
        projectPath: String,
        worktreePath: String,
        branch: String?,
        identityValidation: WorktreeRemovalIdentityValidation
    ) async throws {
        try requireProjectIdentity(identityValidation.project, at: projectPath)
        try requireWorktreeIdentity(identityValidation, at: worktreePath)
        let listResult = try await shell.run(
            executable: "/usr/bin/git",
            args: ["worktree", "list", "--porcelain"],
            in: projectPath
        )
        guard listResult.succeeded else {
            throw Self.makeGitError(from: listResult)
        }
        try requireProjectIdentity(identityValidation.project, at: projectPath)
        try requireWorktreeIdentity(identityValidation, at: worktreePath)

        let branchOID = try validatedRemovalBranchOID(
            projectPath: projectPath,
            worktreePath: worktreePath,
            branch: branch,
            worktreeListOutput: listResult.stdout
        )
        try requireProjectIdentity(identityValidation.project, at: projectPath)
        try requireWorktreeIdentity(identityValidation, at: worktreePath)
        try await runTeardownScriptIfNeeded(
            projectPath: projectPath,
            worktreePath: worktreePath,
            branch: branch,
            identityValidation: identityValidation
        )
        try requireProjectIdentity(identityValidation.project, at: projectPath)
        try requireWorktreeIdentity(identityValidation, at: worktreePath)

        let removeResult = try await removeWorktree(
            projectPath: projectPath,
            worktreePath: worktreePath,
            identityValidation: identityValidation
        )
        guard removeResult.succeeded else {
            throw Self.makeGitError(from: removeResult)
        }

        if let branch, let branchOID {
            try await deleteBranchValidated(
                projectPath: projectPath,
                branch: branch,
                expectedOID: branchOID,
                expectedProjectIdentity: identityValidation.project
            )
        }
    }

    private func validatedRemovalBranchOID(
        projectPath: String,
        worktreePath: String,
        branch: String?,
        worktreeListOutput: String
    ) throws -> String? {
        let canonicalProjectPath = CanonicalPath.normalize(projectPath)
        let canonicalWorktreePath = CanonicalPath.normalize(worktreePath)
        let registeredWorktree = parseWorktreeList(worktreeListOutput).first {
            CanonicalPath.normalize($0.path) == canonicalWorktreePath
        }
        guard registeredWorktree != nil, canonicalProjectPath != canonicalWorktreePath else {
            throw GitError.commandFailed("Refusing to remove: \(worktreePath) is not a removable worktree")
        }
        guard let branch else {
            return nil
        }
        guard registeredWorktree?.branch == branch,
              let branchOID = registeredWorktree?.headOID else {
            throw GitError.commandFailed(
                "Refusing to delete branch \(branch) because its worktree ref identity could not be proven"
            )
        }
        return branchOID
    }
}

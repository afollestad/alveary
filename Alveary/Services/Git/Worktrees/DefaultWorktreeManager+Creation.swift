import Foundation

struct WorktreeTarget {
    let path: String
    let branch: String
}

struct PreparedWorktreeCreation {
    let projectPath: String
    let threadName: String
    let target: WorktreeTarget
    let resolvedBase: String
    let worktreesBase: String
    let expectedProjectIdentity: TaskWorkspaceFileSystemIdentity?
    let expectedTargetParentIdentity: TaskWorkspaceFileSystemIdentity?
}

private struct WorktreeCreationResult {
    let info: WorktreeInfo
    let worktreeIdentity: TaskWorkspaceFileSystemIdentity?
}

extension DefaultWorktreeManager {
    func create(
        projectPath: String,
        threadName: String,
        baseRef: String?,
        remoteName: String?
    ) async throws -> WorktreeInfo {
        try await createValidated(
            projectPath: projectPath,
            threadName: threadName,
            baseRef: baseRef,
            remoteName: remoteName,
            provenanceContext: nil
        ).info
    }

    func create(
        projectPath: String,
        threadName: String,
        baseRef: String?,
        remoteName: String?,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity
    ) async throws -> IdentityValidatedWorktreeInfo {
        try await create(
            projectPath: projectPath,
            threadName: threadName,
            baseRef: baseRef,
            remoteName: remoteName,
            provenanceContext: WorktreeCreationProvenanceContext(
                expectedProjectIdentity: expectedProjectIdentity,
                recorder: { _ in }
            )
        )
    }

    func create(
        projectPath: String,
        threadName: String,
        baseRef: String?,
        remoteName: String?,
        provenanceContext: WorktreeCreationProvenanceContext
    ) async throws -> IdentityValidatedWorktreeInfo {
        let created = try await createValidated(
            projectPath: projectPath,
            threadName: threadName,
            baseRef: baseRef,
            remoteName: remoteName,
            provenanceContext: provenanceContext
        )
        guard let worktreeIdentity = created.worktreeIdentity else {
            throw WorktreeSourceValidationError.ownedWorktreeChanged(created.info.path)
        }
        return IdentityValidatedWorktreeInfo(
            info: created.info,
            sourceProjectIdentity: provenanceContext.expectedProjectIdentity,
            worktreeIdentity: worktreeIdentity
        )
    }

    private func createValidated(
        projectPath: String,
        threadName: String,
        baseRef: String?,
        remoteName: String?,
        provenanceContext: WorktreeCreationProvenanceContext?
    ) async throws -> WorktreeCreationResult {
        let expectedProjectIdentity = provenanceContext?.expectedProjectIdentity
        let prepared = try await prepareWorktreeCreation(
            projectPath: projectPath,
            threadName: threadName,
            baseRef: baseRef,
            remoteName: remoteName,
            expectedProjectIdentity: expectedProjectIdentity
        )
        return try await createPreparedWorktree(prepared, provenanceContext: provenanceContext)
    }

    private func prepareWorktreeCreation(
        projectPath: String,
        threadName: String,
        baseRef: String?,
        remoteName: String?,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity?
    ) async throws -> PreparedWorktreeCreation {
        try requireProjectIdentity(expectedProjectIdentity, at: projectPath)
        let settings = await MainActor.run { settingsService.current }
        try requireProjectIdentity(expectedProjectIdentity, at: projectPath)
        try await validateIdentityAwareCreationSettings(
            settings,
            projectPath: projectPath,
            expectedProjectIdentity: expectedProjectIdentity
        )
        let target = try await resolveWorktreeTarget(
            projectPath: projectPath,
            threadName: threadName,
            branchPrefix: settings.branchPrefix,
            worktreesBase: settings.expandedWorktreesBaseDirectory,
            expectedProjectIdentity: expectedProjectIdentity
        )
        let resolvedBase = try await resolveBaseRef(
            projectPath: projectPath,
            baseRef: baseRef,
            remoteName: remoteName,
            expectedProjectIdentity: expectedProjectIdentity
        )
        try await validateIdentityAwareCreationTarget(
            target,
            resolvedBase: resolvedBase,
            settings: settings,
            projectPath: projectPath,
            expectedProjectIdentity: expectedProjectIdentity
        )
        let expectedTargetParentIdentity = try captureWorktreeTargetParentIdentity(
            targetPath: target.path,
            expectedProjectIdentity: expectedProjectIdentity
        )
        return PreparedWorktreeCreation(
            projectPath: projectPath,
            threadName: threadName,
            target: target,
            resolvedBase: resolvedBase,
            worktreesBase: settings.expandedWorktreesBaseDirectory,
            expectedProjectIdentity: expectedProjectIdentity,
            expectedTargetParentIdentity: expectedTargetParentIdentity
        )
    }

    private func validateIdentityAwareCreationSettings(
        _ settings: AppSettings,
        projectPath: String,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity?
    ) async throws {
        guard expectedProjectIdentity != nil else {
            return
        }
        try validateWorktreeDestination(
            projectPath: projectPath,
            worktreesBase: settings.expandedWorktreesBaseDirectory
        )
        try await validateBranchPrefix(
            settings.branchPrefix,
            projectPath: projectPath,
            expectedProjectIdentity: expectedProjectIdentity
        )
    }

    private func validateIdentityAwareCreationTarget(
        _ target: WorktreeTarget,
        resolvedBase: String,
        settings: AppSettings,
        projectPath: String,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity?
    ) async throws {
        guard expectedProjectIdentity != nil else {
            try ensureWorktreeParentDirectoryExists(for: target.path)
            return
        }
        try await validateResolvedBase(
            resolvedBase,
            projectPath: projectPath,
            expectedProjectIdentity: expectedProjectIdentity
        )
        try validateWorktreeDestination(
            projectPath: projectPath,
            worktreesBase: settings.expandedWorktreesBaseDirectory
        )
        try validateWorktreeTargetIsAvailable(target.path)
        try requireProjectIdentity(expectedProjectIdentity, at: projectPath)
        try ensureWorktreeParentDirectoryExists(for: target.path)
        try validateWorktreeDestination(
            projectPath: projectPath,
            worktreesBase: settings.expandedWorktreesBaseDirectory
        )
        try validateWorktreeTargetIsAvailable(target.path)
    }

    private func createPreparedWorktree(
        _ prepared: PreparedWorktreeCreation,
        provenanceContext: WorktreeCreationProvenanceContext?
    ) async throws -> WorktreeCreationResult {
        var worktreeIdentity: TaskWorkspaceFileSystemIdentity?
        var branchIsOwned = false
        var branchOID: String?
        try await recordInitialCreationProvenance(prepared, context: provenanceContext)
        do {
            worktreeIdentity = try createIdentityAwareTarget(prepared)
            try validateCreatedWorktreeTarget(
                prepared,
                worktreeIdentity: worktreeIdentity
            )
            try await recordCreationProvenance(
                prepared: prepared,
                worktreeIdentity: worktreeIdentity,
                branchIsOwned: false,
                branchOID: nil,
                context: provenanceContext
            )
            try await addPreparedWorktree(
                prepared,
                worktreeIdentity: worktreeIdentity
            )
            let createdBranchOID = try await captureCreatedBranchOID(
                prepared,
                worktreeIdentity: worktreeIdentity
            )
            branchOID = createdBranchOID
            branchIsOwned = true
            try await recordCreationProvenance(
                prepared: prepared,
                worktreeIdentity: worktreeIdentity,
                branchIsOwned: true,
                branchOID: createdBranchOID,
                context: provenanceContext
            )
            return try await configurePreparedWorktree(
                prepared,
                worktreeIdentity: worktreeIdentity,
                branchOID: createdBranchOID
            )
        } catch {
            try await throwCreationFailure(
                error,
                prepared: prepared,
                rollback: WorktreeCreationRollbackState(
                    worktreeIdentity: worktreeIdentity, branchIsOwned: branchIsOwned,
                    branchOID: branchOID,
                    provenanceContext: provenanceContext
                )
            )
        }
    }

    private func recordInitialCreationProvenance(
        _ prepared: PreparedWorktreeCreation,
        context: WorktreeCreationProvenanceContext?
    ) async throws {
        try await recordCreationProvenance(
            prepared: prepared,
            worktreeIdentity: nil,
            branchIsOwned: false,
            branchOID: nil,
            context: context
        )
    }

    private func createIdentityAwareTarget(
        _ prepared: PreparedWorktreeCreation
    ) throws -> TaskWorkspaceFileSystemIdentity? {
        guard prepared.expectedProjectIdentity != nil else {
            return nil
        }
        try requireProjectIdentity(prepared.expectedProjectIdentity, at: prepared.projectPath)
        try validateWorktreeTargetParent(
            targetPath: prepared.target.path,
            projectPath: prepared.projectPath,
            worktreesBase: prepared.worktreesBase,
            expectedParentIdentity: prepared.expectedTargetParentIdentity
        )
        try validateWorktreeTargetIsAvailable(prepared.target.path)
        try directoryCreator(prepared.target.path)
        guard let createdIdentity = currentDirectoryIdentity(at: prepared.target.path) else {
            throw WorktreeSourceValidationError.ownedWorktreeChanged(prepared.target.path)
        }
        try requireCreationIdentities(
            WorktreeCreationIdentityValidation(
                project: prepared.expectedProjectIdentity,
                worktree: createdIdentity
            ),
            projectPath: prepared.projectPath,
            worktreePath: prepared.target.path
        )
        return createdIdentity
    }

    func recordCreationProvenance(
        prepared: PreparedWorktreeCreation,
        worktreeIdentity: TaskWorkspaceFileSystemIdentity?,
        branchIsOwned: Bool,
        branchOID: String?,
        context: WorktreeCreationProvenanceContext?
    ) async throws {
        guard let context else {
            return
        }
        try await context.recorder(
            makeFailedCreationCleanup(
                prepared: prepared,
                sourceProjectIdentity: context.expectedProjectIdentity,
                worktreeIdentity: worktreeIdentity,
                branchIsOwned: branchIsOwned,
                branchOID: branchOID
            )
        )
    }

    private func makeFailedCreationCleanup(
        prepared: PreparedWorktreeCreation,
        sourceProjectIdentity: TaskWorkspaceFileSystemIdentity,
        worktreeIdentity: TaskWorkspaceFileSystemIdentity?,
        branchIsOwned: Bool,
        branchOID: String?
    ) -> FailedWorktreeCreationCleanup {
        FailedWorktreeCreationCleanup(
            sourceProjectPath: prepared.projectPath,
            worktreePath: prepared.target.path,
            branch: prepared.target.branch,
            sourceProjectIdentity: sourceProjectIdentity,
            worktreeIdentity: worktreeIdentity,
            branchIsOwned: branchIsOwned,
            branchOID: branchOID
        )
    }

    private func addPreparedWorktree(
        _ prepared: PreparedWorktreeCreation,
        worktreeIdentity: TaskWorkspaceFileSystemIdentity?
    ) async throws {
        let identityValidation = WorktreeCreationIdentityValidation(
            project: prepared.expectedProjectIdentity,
            worktree: worktreeIdentity
        )
        try requireCreationIdentities(
            identityValidation,
            projectPath: prepared.projectPath,
            worktreePath: prepared.target.path
        )
        let result: ShellResult
        do {
            result = try await shell.run(
                executable: "/usr/bin/git",
                args: [
                    "worktree", "add", "--no-track", "-b",
                    prepared.target.branch, prepared.target.path, prepared.resolvedBase
                ],
                in: prepared.projectPath
            )
        } catch {
            try requireCreationIdentities(
                identityValidation,
                projectPath: prepared.projectPath,
                worktreePath: prepared.target.path
            )
            throw error
        }
        try requireCreationIdentities(
            identityValidation,
            projectPath: prepared.projectPath,
            worktreePath: prepared.target.path
        )
        guard result.succeeded else {
            throw Self.makeGitError(from: result)
        }
    }

    private func configurePreparedWorktree(
        _ prepared: PreparedWorktreeCreation,
        worktreeIdentity: TaskWorkspaceFileSystemIdentity?,
        branchOID: String
    ) async throws -> WorktreeCreationResult {
        let identityValidation = WorktreeCreationIdentityValidation(
            project: prepared.expectedProjectIdentity,
            worktree: worktreeIdentity
        )
        try await postCreateSetup(
            projectPath: prepared.projectPath,
            worktreePath: prepared.target.path,
            threadName: prepared.threadName,
            branch: prepared.target.branch,
            identityValidation: identityValidation
        )
        try requireCreationIdentities(
            identityValidation,
            projectPath: prepared.projectPath,
            worktreePath: prepared.target.path
        )
        let resultPath = worktreeIdentity == nil
            ? CanonicalPath.normalize(prepared.target.path)
            : prepared.target.path
        return WorktreeCreationResult(
            info: WorktreeInfo(
                path: resultPath,
                branch: prepared.target.branch,
                headOID: branchOID
            ),
            worktreeIdentity: worktreeIdentity
        )
    }

    func createFromBranch(
        projectPath: String,
        threadName: String,
        branch: String,
        remoteName: String?
    ) async throws -> WorktreeInfo {
        let settings = await MainActor.run { settingsService.current }
        let worktreePath = resolveUniqueWorktreePath(
            projectPath: projectPath,
            threadName: threadName,
            worktreesBase: settings.expandedWorktreesBaseDirectory
        )
        if let remoteName {
            _ = try? await shell.run(
                executable: "/usr/bin/git",
                args: ["fetch", remoteName, branch],
                in: projectPath,
                timeout: .seconds(30)
            )
        }
        try ensureWorktreeParentDirectoryExists(for: worktreePath)

        do {
            let result = try await shell.run(
                executable: "/usr/bin/git",
                args: ["worktree", "add", worktreePath, branch],
                in: projectPath
            )
            guard result.succeeded else {
                throw Self.makeGitError(from: result)
            }
            try await postCreateSetup(
                projectPath: projectPath,
                worktreePath: worktreePath,
                threadName: threadName,
                branch: branch,
                identityValidation: .unchecked
            )
            return WorktreeInfo(path: CanonicalPath.normalize(worktreePath), branch: branch)
        } catch {
            try await throwCreateFromBranchFailure(
                error,
                projectPath: projectPath,
                worktreePath: worktreePath
            )
        }
    }

}

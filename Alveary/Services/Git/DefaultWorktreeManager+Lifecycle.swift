import Foundation

struct WorktreeCreationIdentityValidation: Sendable {
    static let unchecked = WorktreeCreationIdentityValidation(project: nil, worktree: nil)

    let project: TaskWorkspaceFileSystemIdentity?
    let worktree: TaskWorkspaceFileSystemIdentity?

    var validatesWorktree: Bool { project != nil }
}

struct WorktreeSetupFailure: Error {
    let message: String
}

private struct WorktreeLifecycleContext {
    let projectPath: String
    let worktreePath: String
    let threadName: String
    let branch: String
}

extension DefaultWorktreeManager {
    func refreshRollbackBranchOID(
        _ prepared: PreparedWorktreeCreation,
        worktreeIdentity: TaskWorkspaceFileSystemIdentity?,
        branchIsOwned: Bool,
        branchOID: String?,
        provenanceContext: WorktreeCreationProvenanceContext?
    ) async -> String? {
        guard branchIsOwned, let branchOID else {
            return nil
        }
        guard let refreshedOID = try? await captureCreatedBranchOID(
            prepared,
            worktreeIdentity: worktreeIdentity
        ) else {
            return branchOID
        }
        guard refreshedOID != branchOID, let provenanceContext else {
            return refreshedOID
        }
        do {
            try await recordCreationProvenance(
                prepared: prepared,
                worktreeIdentity: worktreeIdentity,
                branchIsOwned: true,
                branchOID: refreshedOID,
                context: provenanceContext
            )
            return refreshedOID
        } catch {
            return branchOID
        }
    }

    func postCreateSetup(
        projectPath: String,
        worktreePath: String,
        threadName: String,
        branch: String,
        identityValidation: WorktreeCreationIdentityValidation
    ) async throws {
        try requireCreationIdentities(
            identityValidation,
            projectPath: projectPath,
            worktreePath: worktreePath
        )
        let config = await projectConfigLoader(projectPath)
        try requireCreationIdentities(
            identityValidation,
            projectPath: projectPath,
            worktreePath: worktreePath
        )
        try preserveFiles(from: projectPath, to: worktreePath, patterns: config.preservePatterns)
        try requireCreationIdentities(
            identityValidation,
            projectPath: projectPath,
            worktreePath: worktreePath
        )

        guard config.setupScript != nil else { return }

        let failureMessage = try await runSetupScript(
            context: WorktreeLifecycleContext(
                projectPath: projectPath,
                worktreePath: worktreePath,
                threadName: threadName,
                branch: branch
            ),
            config: config,
            identityValidation: identityValidation
        )
        guard let failureMessage else {
            return
        }
        throw WorktreeSetupFailure(message: failureMessage)
    }

    private func runSetupScript(
        context: WorktreeLifecycleContext,
        config: AlvearyProjectConfig,
        identityValidation: WorktreeCreationIdentityValidation
    ) async throws -> String? {
        guard let setupScript = config.setupScript else {
            return nil
        }

        try requireCreationIdentities(
            identityValidation,
            projectPath: context.projectPath,
            worktreePath: context.worktreePath
        )
        let result: ShellResult
        do {
            result = try await shell.run(
                executable: "/bin/sh",
                args: ["-c", setupScript],
                in: context.worktreePath,
                environment: buildLifecycleScriptEnvironment(
                    projectPath: context.projectPath,
                    worktreePath: context.worktreePath,
                    threadName: context.threadName,
                    branch: context.branch
                ),
                timeout: .seconds(config.setupTimeoutSeconds ?? 300)
            )
        } catch {
            try requireCreationIdentities(
                identityValidation,
                projectPath: context.projectPath,
                worktreePath: context.worktreePath
            )
            return error.localizedDescription
        }
        try requireCreationIdentities(
            identityValidation,
            projectPath: context.projectPath,
            worktreePath: context.worktreePath
        )
        return result.succeeded
            ? nil
            : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func runTeardownScriptIfNeeded(
        projectPath: String,
        worktreePath: String,
        branch: String?,
        identityValidation: WorktreeRemovalIdentityValidation = .unchecked
    ) async throws {
        try requireProjectIdentity(identityValidation.project, at: projectPath)
        try requireWorktreeIdentity(identityValidation, at: worktreePath)
        let config = await projectConfigLoader(projectPath)
        try requireProjectIdentity(identityValidation.project, at: projectPath)
        try requireWorktreeIdentity(identityValidation, at: worktreePath)
        guard let teardownScript = config.teardownScript else {
            return
        }

        try requireProjectIdentity(identityValidation.project, at: projectPath)
        try requireWorktreeIdentity(identityValidation, at: worktreePath)
        _ = try? await shell.run(
            executable: "/bin/sh",
            args: ["-c", teardownScript],
            in: worktreePath,
            environment: buildLifecycleScriptEnvironment(
                projectPath: projectPath,
                worktreePath: worktreePath,
                threadName: URL(fileURLWithPath: worktreePath).lastPathComponent,
                branch: branch
            ),
            timeout: .seconds(60)
        )
        try requireProjectIdentity(identityValidation.project, at: projectPath)
        try requireWorktreeIdentity(identityValidation, at: worktreePath)
    }

    // Runs the partial-worktree cleanup as a detached child task so the caller's cancellation
    // cannot abort the shell commands we need to remove the on-disk worktree and rollback branch.
    // `rollbackBranch` is nil when the caller is `createFromBranch`, which reuses an existing
    // branch and therefore has nothing branch-side to roll back.
    func detachedCleanupAfterFailedCreate(
        projectPath: String,
        worktreePath: String,
        rollbackBranch: String?,
        rollbackBranchOID: String?,
        identityValidation: WorktreeCreationIdentityValidation
    ) async -> Bool {
        let cleanup = Task.detached { [weak self] in
            guard let self else { return true }
            return await self.cleanupFailedSetup(
                projectPath: projectPath,
                worktreePath: worktreePath,
                rollbackBranch: rollbackBranch,
                rollbackBranchOID: rollbackBranchOID,
                identityValidation: identityValidation
            )
        }
        return await cleanup.value
    }

    func cleanupFailedSetup(
        projectPath: String,
        worktreePath: String,
        rollbackBranch: String?,
        rollbackBranchOID: String?,
        identityValidation: WorktreeCreationIdentityValidation
    ) async -> Bool {
        let removeResult = try? await removeWorktree(
            projectPath: projectPath,
            worktreePath: worktreePath,
            identityValidation: WorktreeRemovalIdentityValidation(
                project: identityValidation.project,
                worktree: identityValidation.worktree,
                validatesWorktree: identityValidation.validatesWorktree
            )
        )
        let rollbackBranchDeleteFailed = await rollbackBranchDeleteFailed(
            projectPath: projectPath,
            rollbackBranch: rollbackBranch,
            rollbackBranchOID: rollbackBranchOID,
            expectedProjectIdentity: identityValidation.project
        )
        let worktreeRemovalFailed = removeResult?.succeeded != true || pathEntryExists(atPath: worktreePath)
        return worktreeRemovalFailed || rollbackBranchDeleteFailed
    }

    func rollbackBranchDeleteFailed(
        projectPath: String,
        rollbackBranch: String?,
        rollbackBranchOID: String?,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity?
    ) async -> Bool {
        guard let rollbackBranch else {
            return false
        }
        guard let rollbackBranchOID else {
            return true
        }

        do {
            try await deleteBranchValidated(
                projectPath: projectPath,
                branch: rollbackBranch,
                expectedOID: rollbackBranchOID,
                expectedProjectIdentity: expectedProjectIdentity
            )
            return false
        } catch {
            return true
        }
    }

    func requireCreationIdentities(
        _ validation: WorktreeCreationIdentityValidation,
        projectPath: String,
        worktreePath: String
    ) throws {
        try requireProjectIdentity(validation.project, at: projectPath)
        guard validation.validatesWorktree else {
            return
        }
        guard let expectedWorktreeIdentity = validation.worktree,
              CanonicalPath.normalize(worktreePath) == worktreePath,
              currentDirectoryIdentity(at: worktreePath) == expectedWorktreeIdentity else {
            throw WorktreeSourceValidationError.ownedWorktreeChanged(worktreePath)
        }
    }

    func buildLifecycleScriptEnvironment(
        projectPath: String,
        worktreePath: String,
        threadName: String,
        branch: String?
    ) -> [String: String] {
        var environment: [String: String] = [
            "ALVEARY_THREAD_NAME": threadName,
            "ALVEARY_PROJECT_PATH": projectPath,
            "ALVEARY_WORKTREE_PATH": worktreePath,
            "ALVEARY_PORT_SEED": shortHash(branch ?? worktreePath)
        ]

        if let branch {
            environment["ALVEARY_BRANCH_NAME"] = branch
        }

        return environment
    }
}

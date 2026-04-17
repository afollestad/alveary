import Foundation

extension DefaultWorktreeManager {
    func postCreateSetup(
        projectPath: String,
        worktreePath: String,
        threadName: String,
        branch: String,
        rollbackBranch: String?
    ) async throws {
        let config = await AlvearyProjectConfig(projectPath: projectPath)
        try preserveFiles(from: projectPath, to: worktreePath, patterns: config.preservePatterns)

        guard config.setupScript != nil else { return }

        let failureMessage = await runSetupScript(
            projectPath: projectPath,
            worktreePath: worktreePath,
            threadName: threadName,
            branch: branch,
            config: config
        )
        guard let failureMessage else {
            return
        }

        if try await cleanupFailedSetup(
            projectPath: projectPath,
            worktreePath: worktreePath,
            rollbackBranch: rollbackBranch
        ) {
            throw GitError.commandFailed(
                "Setup script failed: \(failureMessage). Cleanup also failed for worktree \(worktreePath)."
            )
        }

        throw GitError.commandFailed("Setup script failed: \(failureMessage)")
    }

    func runSetupScript(
        projectPath: String,
        worktreePath: String,
        threadName: String,
        branch: String,
        config: AlvearyProjectConfig
    ) async -> String? {
        guard let setupScript = config.setupScript else {
            return nil
        }

        do {
            let result = try await shell.run(
                executable: "/bin/sh",
                args: ["-c", setupScript],
                in: worktreePath,
                environment: buildLifecycleScriptEnvironment(
                    projectPath: projectPath,
                    worktreePath: worktreePath,
                    threadName: threadName,
                    branch: branch
                ),
                timeout: .seconds(config.setupTimeoutSeconds ?? 300)
            )
            return result.succeeded
                ? nil
                : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return error.localizedDescription
        }
    }

    func runTeardownScriptIfNeeded(
        projectPath: String,
        worktreePath: String,
        branch: String?
    ) async {
        let config = await AlvearyProjectConfig(projectPath: projectPath)
        guard let teardownScript = config.teardownScript else {
            return
        }

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
    }

    // Runs the partial-worktree cleanup as a detached child task so the caller's cancellation
    // cannot abort the shell commands we need to remove the on-disk worktree and rollback branch.
    // `rollbackBranch` is nil when the caller is `createFromBranch`, which reuses an existing
    // branch and therefore has nothing branch-side to roll back.
    func detachedCleanupAfterFailedCreate(
        projectPath: String,
        worktreePath: String,
        rollbackBranch: String?
    ) async {
        let cleanup = Task.detached { [weak self] in
            guard let self else { return }
            _ = try? await self.cleanupFailedSetup(
                projectPath: projectPath,
                worktreePath: worktreePath,
                rollbackBranch: rollbackBranch
            )
        }
        await cleanup.value
    }

    func cleanupFailedSetup(
        projectPath: String,
        worktreePath: String,
        rollbackBranch: String?
    ) async throws -> Bool {
        let removeResult = try? await removeWorktree(projectPath: projectPath, worktreePath: worktreePath)
        let rollbackBranchDeleteFailed = try await rollbackBranchDeleteFailed(
            projectPath: projectPath,
            rollbackBranch: rollbackBranch
        )
        return removeResult?.succeeded != true || rollbackBranchDeleteFailed
    }

    func rollbackBranchDeleteFailed(projectPath: String, rollbackBranch: String?) async throws -> Bool {
        guard let rollbackBranch else {
            return false
        }

        let deleteResult = try? await shell.run(
            executable: "/usr/bin/git",
            args: ["branch", "-D", rollbackBranch],
            in: projectPath
        )
        return deleteResult?.succeeded == false
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

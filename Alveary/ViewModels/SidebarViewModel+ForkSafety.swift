import Foundation

extension SidebarViewModel {
    func completeForkBootstrap(_ target: ThreadForkTargetSnapshot) throws {
        guard let dbThread = modelContext.resolveThread(id: target.threadID) else {
            throw SidebarViewModelError.threadMissing
        }
        dbThread.hasCompletedInitialSetup = true
        dbThread.isForkBootstrapPending = false
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        NotificationCenter.default.post(name: .threadPresentationChanged, object: dbThread)
    }

    func rollbackFailedFork(
        target: ThreadForkTargetSnapshot,
        originalError: Error
    ) async throws {
        do {
            if let dbThread = modelContext.resolveThread(id: target.threadID) {
                try requireNoForkRollbackAttachments(dbThread)
            }
            let resolution = await providerSessionActionService.resolveSessions(matching: target.providerSessionActionSnapshot)
            let diagnostics = await providerSessionActionService.deleteSessions(ProviderSessionActionResolution(
                snapshot: resolution.snapshot,
                records: resolution.records,
                missingBindings: []
            ))
            presentProviderSessionActionDiagnostics(diagnostics)

            if let dbThread = modelContext.resolveThread(id: target.threadID) {
                try requireNoForkRollbackAttachments(dbThread)
                modelContext.delete(dbThread)
                try modelContext.save()
            }

            try await removeForkWorktreeIfUnclaimed(target.worktree, projectPath: target.projectPath)
        } catch {
            throw SidebarViewModelError.threadForkRollbackFailed(original: originalError, cleanup: error)
        }
    }

    private func requireNoForkRollbackAttachments(_ thread: AgentThread) throws {
        guard thread.targetedScheduledTasks.isEmpty,
              thread.targetedScheduledTaskRuns.isEmpty else {
            throw SidebarViewModelError.forkRollbackBlockedBySchedule
        }
    }

    private func removeForkWorktreeIfUnclaimed(
        _ worktree: ForkCreatedWorktree?,
        projectPath: String
    ) async throws {
        guard let worktree else {
            return
        }
        guard let expectedStatus = worktree.expectedStatus,
              await gitStatusSnapshot(in: worktree.info.path) == expectedStatus else {
            return
        }

        try await worktreeManager.remove(
            projectPath: projectPath,
            worktreePath: worktree.info.path,
            branch: worktree.info.branch
        )
    }

    func gitStatusSnapshot(in directory: String) async -> String? {
        let result = try? await shell.run(
            executable: "/usr/bin/git",
            args: ["status", "--porcelain=v1", "--untracked-files=all"],
            in: directory
        )
        guard result?.succeeded == true else {
            return nil
        }
        return result?.stdout
    }
}

import Foundation
import SwiftData

extension SidebarViewModel {
    func cleanupPendingScheduledWorktreeBeforeThreadDeletion(
        _ snapshot: ThreadCleanupSnapshot
    ) async throws {
        guard let cleanup = snapshot.pendingScheduledWorktreeCleanup else {
            return
        }
        try await cleanupPendingScheduledWorktree(cleanup, runID: snapshot.scheduledTaskRunID)
    }
}

extension SidebarViewModel {
    func cleanupPendingScheduledWorktree(
        _ cleanup: ScheduledWorktreeCleanupProvenance,
        runID: PersistentIdentifier?
    ) async throws {
        guard let runID else {
            throw SidebarViewModelError.threadMissingDeletionMetadata
        }
        guard activeScheduledCleanupRunIDs.insert(runID).inserted else {
            throw TaskWorkspaceCleanupError.pendingScheduledCleanupAlreadyInProgress
        }
        defer { activeScheduledCleanupRunIDs.remove(runID) }

        if try completeRetiredPendingWorktreeCleanup(
            cleanup,
            runID: runID
        ) {
            return
        }
        let worktreeIdentity = try pendingWorktreeIdentity(cleanup)
        try requirePendingCleanupSourceCurrent(cleanup, worktreeIdentity: worktreeIdentity, runID: runID)
        let worktrees = try await listPendingCleanupWorktrees(
            cleanup,
            worktreeIdentity: worktreeIdentity,
            runID: runID
        )
        try requirePendingCleanupSourceCurrent(cleanup, worktreeIdentity: worktreeIdentity, runID: runID)
        let branchCleanupError = try await performPendingGitCleanup(
            cleanup,
            runID: runID,
            worktreeIdentity: worktreeIdentity,
            listedWorktrees: worktrees
        )
        try finalizePendingWorktreeCleanup(
            cleanup,
            runID: runID,
            worktreeIdentity: worktreeIdentity,
            branchCleanupError: branchCleanupError
        )
    }

    private func finalizePendingWorktreeCleanup(
        _ cleanup: ScheduledWorktreeCleanupProvenance,
        runID: PersistentIdentifier,
        worktreeIdentity: TaskWorkspaceFileSystemIdentity?,
        branchCleanupError: Error?
    ) throws {
        do {
            try removePendingWorktreePath(cleanup, worktreeIdentity: worktreeIdentity)
            if branchCleanupError == nil {
                try updatePendingWorktreeCleanupRun(runID: runID) { run in
                    run.clearPendingWorktreeCleanup()
                }
            } else {
                try updatePendingWorktreeCleanupRun(runID: runID) { run in
                    run.clearPendingWorktreeOwnershipCleanup()
                }
            }
        } catch {
            if let branchCleanupError {
                throw TaskWorkspaceCleanupError.pendingGitAndFallbackFailed(
                    gitError: branchCleanupError,
                    fallbackError: error
                )
            }
            throw error
        }
        if let branchCleanupError {
            throw TaskWorkspaceCleanupError.pendingGitCleanupFailed(branchCleanupError)
        }
    }

    private func requirePendingCleanupSourceCurrent(
        _ cleanup: ScheduledWorktreeCleanupProvenance,
        worktreeIdentity: TaskWorkspaceFileSystemIdentity?,
        runID: PersistentIdentifier
    ) throws {
        guard pendingCleanupSourceIsCurrent(cleanup) else {
            try removePendingWorktreePathAndRetireBranchOwnership(
                cleanup,
                worktreeIdentity: worktreeIdentity,
                runID: runID
            )
            throw TaskWorkspaceCleanupError.sourceProjectChanged(cleanup.sourceProjectPath)
        }
    }

    private func listPendingCleanupWorktrees(
        _ cleanup: ScheduledWorktreeCleanupProvenance,
        worktreeIdentity: TaskWorkspaceFileSystemIdentity?,
        runID: PersistentIdentifier
    ) async throws -> [WorktreeInfo] {
        do {
            return try await worktreeManager.list(projectPath: cleanup.sourceProjectPath)
        } catch {
            try handlePendingGitCleanupFailure(
                error,
                cleanup: cleanup,
                worktreeIdentity: worktreeIdentity,
                runID: runID
            )
        }
    }

    private func performPendingGitCleanup(
        _ cleanup: ScheduledWorktreeCleanupProvenance,
        runID: PersistentIdentifier,
        worktreeIdentity: TaskWorkspaceFileSystemIdentity?,
        listedWorktrees: [WorktreeInfo]
    ) async throws -> Error? {
        do {
            return try await cleanupPendingGitState(
                cleanup,
                runID: runID,
                worktreeIdentity: worktreeIdentity,
                listedWorktrees: listedWorktrees
            )
        } catch {
            try handlePendingGitCleanupFailure(
                error,
                cleanup: cleanup,
                worktreeIdentity: worktreeIdentity,
                runID: runID
            )
        }
    }

    private func cleanupPendingGitState(
        _ cleanup: ScheduledWorktreeCleanupProvenance,
        runID: PersistentIdentifier,
        worktreeIdentity: TaskWorkspaceFileSystemIdentity?,
        listedWorktrees: [WorktreeInfo]
    ) async throws -> Error? {
        let registeredWorktree = listedWorktrees.first(where: {
            CanonicalPath.normalize($0.path) == cleanup.worktreePath
        })
        let durableCleanup = try persistPendingBranchOIDIfProven(
            cleanup,
            runID: runID,
            worktreeIdentity: worktreeIdentity,
            registeredWorktree: registeredWorktree
        )
        if registeredWorktree != nil {
            try await worktreeManager.remove(
                projectPath: durableCleanup.sourceProjectPath,
                worktreePath: durableCleanup.worktreePath,
                branch: nil,
                expectedProjectIdentity: durableCleanup.sourceProjectIdentity,
                expectedWorktreeIdentity: worktreeIdentity
            )
        }

        let branchOwnershipWasRetired = try retirePendingWorktreeBranchOwnership(durableCleanup, runID: runID)
        guard branchOwnershipWasRetired, let expectedOID = durableCleanup.branchOID else {
            return nil
        }
        do {
            try await worktreeManager.deleteBranch(
                projectPath: durableCleanup.sourceProjectPath,
                branch: durableCleanup.branch,
                expectedOID: expectedOID,
                expectedProjectIdentity: durableCleanup.sourceProjectIdentity
            )
        } catch let error as RetryableWorktreeBranchDeletionError {
            try restorePendingWorktreeBranchOwnership(durableCleanup, runID: runID)
            return error
        } catch {
            return error
        }
        return nil
    }

    private func persistPendingBranchOIDIfProven(
        _ cleanup: ScheduledWorktreeCleanupProvenance,
        runID: PersistentIdentifier,
        worktreeIdentity: TaskWorkspaceFileSystemIdentity?,
        registeredWorktree: WorktreeInfo?
    ) throws -> ScheduledWorktreeCleanupProvenance {
        guard let run = modelContext.resolveScheduledTaskRun(id: runID),
              let currentCleanup = run.pendingWorktreeCleanup,
              currentCleanup.identifiesSameBranchCleanup(as: cleanup) else {
            throw SidebarViewModelError.threadMissingDeletionMetadata
        }
        var durableCleanup = currentCleanup
        if currentCleanup.branchIsOwned,
           registeredWorktree?.branch == currentCleanup.branch,
           let registeredBranchOID = registeredWorktree?.headOID {
            guard let worktreeIdentity,
                  CanonicalPath.normalize(currentCleanup.worktreePath) == currentCleanup.worktreePath,
                  pendingCleanupDirectoryIdentity(at: currentCleanup.worktreePath) == worktreeIdentity else {
                return currentCleanup
            }
            durableCleanup = durableCleanup.recordingBranchOID(registeredBranchOID)
        }
        guard durableCleanup != currentCleanup else {
            return durableCleanup
        }
        run.setPendingWorktreeCleanup(durableCleanup)
        try modelContext.save()
        return durableCleanup
    }

    private func pendingWorktreeIdentity(
        _ cleanup: ScheduledWorktreeCleanupProvenance
    ) throws -> TaskWorkspaceFileSystemIdentity? {
        guard let workspace = cleanup.ownedWorkspaceDescriptor else {
            return cleanup.worktreeIdentity
        }
        let recordedIdentity: TaskWorkspaceFileSystemIdentity?
        do {
            recordedIdentity = try taskWorkspaceOwnershipService.ownedWorktreeIdentity(for: workspace)
        } catch let error as TaskWorkspaceOwnershipError {
            guard case .missingOwnershipMarker = error else {
                throw error
            }
            return cleanup.worktreeIdentity
        }
        guard let recordedIdentity else {
            return cleanup.worktreeIdentity
        }
        guard cleanup.worktreeIdentity == nil || cleanup.worktreeIdentity == recordedIdentity else {
            throw SidebarViewModelError.threadMissingDeletionMetadata
        }
        return recordedIdentity
    }

    private func handlePendingGitCleanupFailure(
        _ error: Error,
        cleanup: ScheduledWorktreeCleanupProvenance,
        worktreeIdentity: TaskWorkspaceFileSystemIdentity?,
        runID: PersistentIdentifier
    ) throws -> Never {
        do {
            try removePendingWorktreePathAndRetireBranchOwnership(
                cleanup,
                worktreeIdentity: worktreeIdentity,
                runID: runID
            )
        } catch let fallbackError {
            throw TaskWorkspaceCleanupError.pendingGitAndFallbackFailed(
                gitError: error,
                fallbackError: fallbackError
            )
        }
        throw TaskWorkspaceCleanupError.pendingGitCleanupFailed(error)
    }

    private func completeRetiredPendingWorktreeCleanup(
        _ cleanup: ScheduledWorktreeCleanupProvenance,
        runID: PersistentIdentifier
    ) throws -> Bool {
        guard let run = modelContext.resolveScheduledTaskRun(id: runID),
              let currentCleanup = run.pendingWorktreeCleanup,
              currentCleanup.identifiesSameBranchCleanup(as: cleanup) else {
            throw SidebarViewModelError.threadMissingDeletionMetadata
        }
        guard !currentCleanup.branchIsOwned else {
            return false
        }
        let worktreeIdentity = try pendingWorktreeIdentity(currentCleanup)
        try removePendingWorktreePath(currentCleanup, worktreeIdentity: worktreeIdentity)
        guard let cleanupAfterRemoval = run.pendingWorktreeCleanup,
              cleanupAfterRemoval.identifiesSameBranchCleanup(as: currentCleanup),
              !cleanupAfterRemoval.branchIsOwned else {
            throw SidebarViewModelError.threadMissingDeletionMetadata
        }
        try updatePendingWorktreeCleanupRun(runID: runID) { run in
            run.clearPendingWorktreeCleanup()
        }
        return true
    }

    private func removePendingWorktreePath(
        _ cleanup: ScheduledWorktreeCleanupProvenance,
        worktreeIdentity: TaskWorkspaceFileSystemIdentity?
    ) throws {
        if let workspace = cleanup.ownedWorkspaceDescriptor {
            try taskWorkspaceOwnershipService.removeProvisionalOwnedWorktree(
                workspace,
                expectedWorktreeIdentity: worktreeIdentity
            )
        } else {
            try taskWorkspaceOwnershipService.removeProvisionalWorktree(
                at: cleanup.worktreePath,
                expectedWorktreeIdentity: worktreeIdentity
            )
        }
    }

    private func removePendingWorktreePathAndRetireBranchOwnership(
        _ cleanup: ScheduledWorktreeCleanupProvenance,
        worktreeIdentity: TaskWorkspaceFileSystemIdentity?,
        runID: PersistentIdentifier
    ) throws {
        try removePendingWorktreePath(cleanup, worktreeIdentity: worktreeIdentity)
        _ = try retirePendingWorktreeBranchOwnership(cleanup, runID: runID)
    }

    private func pendingCleanupSourceIsCurrent(_ cleanup: ScheduledWorktreeCleanupProvenance) -> Bool {
        guard CanonicalPath.normalize(cleanup.sourceProjectPath) == cleanup.sourceProjectPath,
              let currentIdentity = try? taskWorkspaceOwnershipService.directoryIdentity(
                  at: cleanup.sourceProjectPath
              ) else {
            return false
        }
        return currentIdentity == cleanup.sourceProjectIdentity
    }

    private func pendingCleanupDirectoryIdentity(at path: String) -> TaskWorkspaceFileSystemIdentity? {
        try? taskWorkspaceOwnershipService.directoryIdentity(at: path)
    }

    private func updatePendingWorktreeCleanupRun(
        runID: PersistentIdentifier,
        mutation: (ScheduledTaskRun) -> Void
    ) throws {
        guard let run = modelContext.resolveScheduledTaskRun(id: runID) else {
            throw SidebarViewModelError.threadMissingDeletionMetadata
        }
        let originalCleanup = run.pendingWorktreeCleanup
        mutation(run)
        do {
            try modelContext.save()
        } catch {
            if let originalCleanup {
                run.setPendingWorktreeCleanup(originalCleanup)
            } else {
                run.clearPendingWorktreeCleanup()
            }
            throw error
        }
    }
}

private extension ScheduledWorktreeCleanupProvenance {
    func identifiesSameBranchCleanup(as other: ScheduledWorktreeCleanupProvenance) -> Bool {
        sourceProjectPath == other.sourceProjectPath &&
            worktreePath == other.worktreePath &&
            branch == other.branch &&
            sourceProjectIdentity == other.sourceProjectIdentity
    }
}

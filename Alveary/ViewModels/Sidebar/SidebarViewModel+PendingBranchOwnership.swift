import SwiftData

extension SidebarViewModel {
    func retirePendingWorktreeBranchOwnership(
        _ cleanup: ScheduledWorktreeCleanupProvenance,
        runID: PersistentIdentifier
    ) throws -> Bool {
        guard let run = modelContext.resolveScheduledTaskRun(id: runID),
              let currentCleanup = run.pendingWorktreeCleanup,
              pendingBranchCleanup(currentCleanup, matches: cleanup) else {
            throw SidebarViewModelError.threadMissingDeletionMetadata
        }
        guard currentCleanup.branchIsOwned else {
            return false
        }
        run.pendingWorktreeCleanupBranchIsOwned = false
        do {
            try modelContext.save()
        } catch {
            run.pendingWorktreeCleanupBranchIsOwned = true
            throw error
        }
        return true
    }

    func restorePendingWorktreeBranchOwnership(
        _ cleanup: ScheduledWorktreeCleanupProvenance,
        runID: PersistentIdentifier
    ) throws {
        guard let run = modelContext.resolveScheduledTaskRun(id: runID),
              let currentCleanup = run.pendingWorktreeCleanup,
              pendingBranchCleanup(currentCleanup, matches: cleanup),
              !currentCleanup.branchIsOwned else {
            throw SidebarViewModelError.threadMissingDeletionMetadata
        }
        run.pendingWorktreeCleanupBranchIsOwned = true
        do {
            try modelContext.save()
        } catch {
            run.pendingWorktreeCleanupBranchIsOwned = false
            throw error
        }
    }

    private func pendingBranchCleanup(
        _ lhs: ScheduledWorktreeCleanupProvenance,
        matches rhs: ScheduledWorktreeCleanupProvenance
    ) -> Bool {
        lhs.sourceProjectPath == rhs.sourceProjectPath &&
            lhs.worktreePath == rhs.worktreePath &&
            lhs.branch == rhs.branch &&
            lhs.sourceProjectIdentity == rhs.sourceProjectIdentity
    }
}

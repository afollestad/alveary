import Foundation

extension SidebarViewModel {
    func commitThreadDeletion(_ snapshot: ThreadCleanupSnapshot) throws {
        try flushPendingModelChangesBeforeDeletion()
        do {
            if let dbThread = modelContext.resolveThread(id: snapshot.threadID) {
                try requireNoScheduledTaskAttachment(dbThread)
                try clearCompletedPendingWorktreeCleanupBeforeThreadDeletion(snapshot)
                try promoteScheduledWorktreeCleanupIfNeeded(snapshot)
                modelContext.delete(dbThread)
                _ = try normalizeSidebarOrderingForLifecycle(
                    excludingThreadIDs: [snapshot.threadID]
                )
                try persistDeletionCommit()
            }
        } catch {
            modelContext.rollback()
            throw error
        }
        invalidateDraftThreadIfNeeded(threadID: snapshot.threadID)
        refreshThreadOrder(animated: true)
        postThreadLifecycleChanged(threadID: snapshot.threadID, mode: snapshot.mode)
    }

    func commitProjectDeletion(
        _ snapshot: ProjectDeletionSnapshot,
        at actionDate: Date = Date()
    ) throws {
        let threadIDs = Set(snapshot.threadSnapshots.map(\.threadID))
        var affectedScheduledTaskIDs: [String] = []
        try flushPendingModelChangesBeforeDeletion()
        do {
            if let dbProject = modelContext.resolveProject(id: snapshot.projectID) {
                try requireNoScheduledTaskAttachments(in: dbProject)
                for threadSnapshot in snapshot.threadSnapshots {
                    try promoteScheduledWorktreeCleanupIfNeeded(threadSnapshot)
                }
                for scheduledTaskID in snapshot.scheduledTaskIDs {
                    guard let scheduledTask = modelContext.resolveScheduledTask(id: scheduledTaskID) else {
                        continue
                    }
                    scheduledTask.pauseForProjectDeletion(at: actionDate)
                    affectedScheduledTaskIDs.append(scheduledTaskID)
                }
                for threadID in snapshot.detachedTaskThreadIDs {
                    modelContext.resolveThread(id: threadID)?.project = nil
                }
                modelContext.delete(dbProject)
                _ = try normalizeSidebarOrderingForLifecycle(
                    excludingProjectIDs: [snapshot.projectID],
                    excludingThreadIDs: threadIDs
                )
                try persistDeletionCommit()
            }
        } catch {
            modelContext.rollback()
            throw error
        }
        invalidateDraftThreadIfNeeded(threadIDs: threadIDs)
        guard !affectedScheduledTaskIDs.isEmpty else {
            return
        }
        NotificationCenter.default.post(
            name: .scheduledTasksChanged,
            object: self,
            userInfo: ["definitionIDs": affectedScheduledTaskIDs]
        )
    }

    private func flushPendingModelChangesBeforeDeletion() throws {
        guard modelContext.hasChanges else {
            return
        }
        try modelContext.save()
    }

    private func promoteScheduledWorktreeCleanupIfNeeded(
        _ snapshot: ThreadCleanupSnapshot
    ) throws {
        guard let cleanup = snapshot.scheduledWorktreeCleanup,
              let runID = snapshot.scheduledTaskRunID,
              let run = modelContext.resolveScheduledTaskRun(id: runID),
              run.workspaceCleanupProvenance == cleanup,
              !run.hasPendingWorktreeCleanupMetadata else {
            if snapshot.scheduledWorktreeCleanup != nil {
                throw SidebarViewModelError.threadMissingDeletionMetadata
            }
            return
        }
        run.setPendingWorktreeCleanup(cleanup)
        run.workspaceCleanupProvenance = nil
    }
}

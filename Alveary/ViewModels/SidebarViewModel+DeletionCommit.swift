import Foundation

extension SidebarViewModel {
    func commitThreadDeletion(_ snapshot: ThreadCleanupSnapshot) throws {
        try flushPendingModelChangesBeforeDeletion()
        do {
            if let dbThread = modelContext.resolveThread(id: snapshot.threadID) {
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
        try flushPendingModelChangesBeforeDeletion()
        do {
            if let dbProject = modelContext.resolveProject(id: snapshot.projectID) {
                for scheduledTaskID in snapshot.scheduledTaskIDs {
                    guard let scheduledTask = modelContext.resolveScheduledTask(id: scheduledTaskID) else {
                        continue
                    }
                    scheduledTask.pauseForProjectDeletion(at: actionDate)
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
    }

    private func flushPendingModelChangesBeforeDeletion() throws {
        guard modelContext.hasChanges else {
            return
        }
        try modelContext.save()
    }
}

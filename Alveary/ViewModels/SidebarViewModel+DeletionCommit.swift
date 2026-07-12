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
    }

    func commitProjectDeletion(_ snapshot: ProjectDeletionSnapshot) throws {
        let threadIDs = Set(snapshot.threadSnapshots.map(\.threadID))
        try flushPendingModelChangesBeforeDeletion()
        do {
            if let dbProject = modelContext.resolveProject(id: snapshot.projectID) {
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

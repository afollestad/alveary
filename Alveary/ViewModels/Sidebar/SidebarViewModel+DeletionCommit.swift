import Foundation

extension SidebarViewModel {
    func commitThreadDeletion(_ snapshot: ThreadCleanupSnapshot) throws {
        var detachedScheduledTaskIDs: [String] = []
        try flushPendingModelChangesBeforeDeletion()
        do {
            if let dbThread = modelContext.resolveThread(id: snapshot.threadID) {
                try requireNoActiveScheduledTaskRun(dbThread)
                try clearCompletedPendingWorktreeCleanupBeforeThreadDeletion(snapshot)
                try promoteScheduledWorktreeCleanupIfNeeded(snapshot)
                // Before the delete, while the row still carries the workspace the surviving
                // schedules inherit. `.nullify` alone would clear the link and leave the
                // destination naming a thread that no longer exists.
                detachedScheduledTaskIDs = ScheduledTaskTargetDetachment.detachTargets(of: dbThread)
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
        NotificationCenter.default.postScheduledTasksDetached(
            object: self,
            definitionIDs: detachedScheduledTaskIDs
        )
    }

    func commitProjectDeletion(
        _ snapshot: ProjectDeletionSnapshot,
        at actionDate: Date = Date()
    ) throws {
        let threadIDs = Set(snapshot.threadSnapshots.map(\.threadID))
        var affectedScheduledTaskIDs = OrderedScheduledTaskIDs()
        try flushPendingModelChangesBeforeDeletion()
        do {
            if let dbProject = modelContext.resolveProject(id: snapshot.projectID) {
                try requireNoActiveScheduledTaskRuns(in: dbProject)
                for threadSnapshot in snapshot.threadSnapshots {
                    try promoteScheduledWorktreeCleanupIfNeeded(threadSnapshot)
                    // Only `threadSnapshots` cascade with the Project; `detachedTaskThreadIDs`
                    // survive it, so schedules targeting those keep their thread.
                    guard let dbThread = modelContext.resolveThread(id: threadSnapshot.threadID) else {
                        continue
                    }
                    affectedScheduledTaskIDs.append(
                        contentsOf: ScheduledTaskTargetDetachment.detachTargets(
                            of: dbThread,
                            continuation: .pauseForProjectDeletion(projectPath: snapshot.projectPath),
                            at: actionDate
                        )
                    )
                }
                for scheduledTaskID in snapshot.scheduledTaskIDs {
                    guard !affectedScheduledTaskIDs.contains(scheduledTaskID),
                          let scheduledTask = modelContext.resolveScheduledTask(id: scheduledTaskID) else {
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
        NotificationCenter.default.postScheduledTasksDetached(
            object: self,
            definitionIDs: affectedScheduledTaskIDs.ids
        )
    }

    /// Order-preserving dedupe for one project deletion's paused definitions. A legacy row can be
    /// both `.existingThread` and Project-backed, and pausing it twice would bump its revision
    /// twice and name it twice in the change notification.
    private struct OrderedScheduledTaskIDs {
        private(set) var ids: [String] = []
        private var seen: Set<String> = []

        func contains(_ id: String) -> Bool {
            seen.contains(id)
        }

        mutating func append(_ id: String) {
            guard seen.insert(id).inserted else {
                return
            }
            ids.append(id)
        }

        mutating func append(contentsOf newIDs: [String]) {
            newIDs.forEach { append($0) }
        }
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

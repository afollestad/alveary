import SwiftData

/// Workspace replacement preserves metadata and releases ownership only after its save.
extension ThreadLifecycleService {
    /// Moves a Task thread onto a workspace resolved after it was created, for a caller that had
    /// to answer before the real one existed — the pull request pane's address-feedback route
    /// answers on the click and settles its checkout behind that return.
    ///
    /// Deliberately does not touch `branch`, `worktreePath`, or `useWorktree`. Those are the
    /// Project-thread field family; a Task carries its checkout in the descriptor alone, and a
    /// non-nil `branch` here would offer the user's live pull request head to `branch -D` on
    /// permanent deletion.
    func replaceTaskWorkspace(
        threadID: PersistentIdentifier, with descriptor: TaskWorkspaceDescriptor, snapshot: WorkspaceSnapshot? = nil
    ) async throws {
        let thread = try requireThread(id: threadID)
        guard thread.effectiveMode == .task else {
            throw SidebarViewModelError.threadMissingTaskWorkspace
        }
        if modelContext.hasChanges { try modelContext.save() }
        let replaced = thread.taskWorkspaceDescriptor
        do {
            thread.taskWorkspaceDescriptor = descriptor
            if let snapshot { thread.workspaceSnapshot = snapshot }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        // Only after the save: the thread must never be left pointing at a directory that is
        // already gone. A private workspace whose thread no longer names it is orphaned, and the
        // next launch's sweep removes it, so a failure here costs disk rather than correctness.
        if let replaced, replaced.ownershipStrategy == .privateOwned, replaced != descriptor {
            let ownership = taskWorkspaceOwnershipService
            _ = try? await Task.detached { try ownership.removeOwnedWorkspace(replaced) }.value
        }
    }

}

import Foundation

/// Workspace access is independent of sidebar placement. Never consult a project's current folders here:
/// a membership edit must not change a suspended session's permissions or a deleted thread's cleanup source.
extension AgentThread {
    /// Private/borrowed Task workspaces and unplaced source workspaces may move through the
    /// standalone sidebar sections without changing execution or filesystem ownership.
    var supportsIndependentSidebarPlacement: Bool { effectiveMode == .task || project == nil }

    var workspaceSnapshot: WorkspaceSnapshot? {
        get { WorkspaceSnapshot.decode(workspaceSnapshotJSON) }
        set { workspaceSnapshotJSON = newValue?.encoded }
    }

    /// Updates folder access without changing the working directory or its ownership.
    func replaceAdditionalFolders(_ folders: [SourceFolderSnapshot], rootsExplicitlyManaged: Bool = true) throws {
        guard let original = workspaceSnapshot else { throw WorkspaceFolderError.invalidSnapshot }
        let updated = WorkspaceSnapshot(
            primarySource: original.primarySource, grants: folders, rootsExplicitlyManaged: rootsExplicitlyManaged
        )
        workspaceSnapshot = updated
        if mode == .task { taskGrantedRoots = updated.grants.map(\.path) }
    }

    var sourceFolder: SourceFolderSnapshot? { workspaceSnapshot?.primarySource }

    var workspaceFolderTargets: [WorkspaceFolderTarget] {
        guard let directory = primaryWorkingDirectory, let snapshot = workspaceSnapshot else { return [] }
        let primary = snapshot.primarySource ?? SourceFolderSnapshot(path: directory)
        let target = WorkspaceFolderTarget(directory: directory, source: primary, isPrimary: true)
        return [target] + snapshot.grants.filter { $0.path != directory }.map {
            WorkspaceFolderTarget(directory: $0.path, source: $0, isPrimary: false)
        }
    }

    /// One ownership resolver for project and Task threads. Only an actual worktree or private marker
    /// grants deletion authority; a shared source folder is always borrowed.
    var resolvedWorkspaceDescriptor: TaskWorkspaceDescriptor? {
        if effectiveMode == .task { return taskWorkspaceDescriptor }
        guard let directory = primaryWorkingDirectory, let snapshot = workspaceSnapshot else { return nil }
        return TaskWorkspaceDescriptor(
            persistedPrimaryRoot: directory,
            persistedGrantedRoots: snapshot.grants.map(\.path),
            ownershipStrategy: worktreePath == nil ? .projectLocal : .projectWorktreeOwned,
            ownershipMarkerID: taskWorkspaceMarkerID,
            persistedSourceProjectPath: snapshot.primarySource?.path
        )
    }
}

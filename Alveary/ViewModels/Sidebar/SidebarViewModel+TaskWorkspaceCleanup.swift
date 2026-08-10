import Foundation

extension SidebarViewModel {
    func cleanupTaskWorkspace(_ snapshot: ThreadCleanupSnapshot) async throws {
        if let pendingCleanup = snapshot.pendingScheduledWorktreeCleanup {
            try await cleanupPendingScheduledWorktree(
                pendingCleanup,
                runID: snapshot.scheduledTaskRunID
            )
            return
        }

        if let scheduledCleanup = snapshot.scheduledWorktreeCleanup {
            try await cleanupPendingScheduledWorktree(
                scheduledCleanup,
                runID: snapshot.scheduledTaskRunID
            )
            return
        }

        guard let workspace = snapshot.taskWorkspace else {
            return
        }

        switch workspace.ownershipStrategy {
        case .privateOwned:
            try taskWorkspaceOwnershipService.removeOwnedWorkspace(workspace)
        case .projectLocal:
            break
        case .projectWorktreeOwned:
            try await cleanupOwnedTaskWorktree(workspace, snapshot: snapshot)
        }
    }
}

private extension SidebarViewModel {
    func cleanupOwnedTaskWorktree(
        _ workspace: TaskWorkspaceDescriptor,
        snapshot: ThreadCleanupSnapshot
    ) async throws {
        do {
            try taskWorkspaceOwnershipService.validateOwnedWorkspaceForRemoval(workspace)
        } catch let identityError as TaskWorkspaceOwnershipError {
            guard case .workspaceIdentityMismatch = identityError else {
                throw identityError
            }
            do {
                try taskWorkspaceOwnershipService.discardOwnedWorktreeRecord(workspace)
            } catch let recordError {
                throw TaskWorkspaceCleanupError.replacementRecordCleanupFailed(
                    identityError: identityError,
                    recordError: recordError
                )
            }
            throw TaskWorkspaceCleanupError.replacementDirectoryPreserved(identityError)
        }
        guard let sourceProjectPath = workspace.sourceProjectPath,
              snapshot.sourceProjectPath == sourceProjectPath else {
            throw SidebarViewModelError.threadMissingDeletionMetadata
        }
        guard let sourceProjectIdentity = currentSourceProjectIdentity(
            for: workspace,
            sourceProjectPath: sourceProjectPath
        ) else {
            try taskWorkspaceOwnershipService.removeOwnedWorkspace(workspace)
            return
        }
        guard let worktreeIdentity = try taskWorkspaceOwnershipService.ownedWorktreeIdentity(for: workspace) else {
            throw SidebarViewModelError.threadMissingDeletionMetadata
        }

        let registeredWorktree = try await registeredTaskWorktree(workspace, sourceProjectPath: sourceProjectPath)
        guard currentDirectoryIdentity(at: sourceProjectPath) == sourceProjectIdentity else {
            try taskWorkspaceOwnershipService.removeOwnedWorkspace(workspace)
            return
        }
        guard let registeredWorktree else {
            try taskWorkspaceOwnershipService.removeOwnedWorkspace(workspace)
            return
        }
        let branchToDelete = snapshot.branch.flatMap { originalBranch in
            registeredWorktree.branch == originalBranch ? originalBranch : nil
        }
        try await removeRegisteredTaskWorktree(
            workspace,
            branch: branchToDelete,
            sourceProjectPath: sourceProjectPath,
            sourceProjectIdentity: sourceProjectIdentity,
            worktreeIdentity: worktreeIdentity
        )
    }

    func currentSourceProjectIdentity(
        for workspace: TaskWorkspaceDescriptor,
        sourceProjectPath: String
    ) -> TaskWorkspaceFileSystemIdentity? {
        guard CanonicalPath.normalize(sourceProjectPath) == sourceProjectPath,
              directoryExists(at: sourceProjectPath),
              let expectedIdentity = try? taskWorkspaceOwnershipService.sourceProjectIdentity(
                  forOwnedWorktree: workspace
              ),
              let currentIdentity = try? taskWorkspaceOwnershipService.directoryIdentity(at: sourceProjectPath) else {
            return nil
        }
        return currentIdentity == expectedIdentity ? expectedIdentity : nil
    }

    func currentDirectoryIdentity(at path: String) -> TaskWorkspaceFileSystemIdentity? {
        try? taskWorkspaceOwnershipService.directoryIdentity(at: path)
    }

    func registeredTaskWorktree(
        _ workspace: TaskWorkspaceDescriptor,
        sourceProjectPath: String
    ) async throws -> WorktreeInfo? {
        do {
            let worktrees = try await worktreeManager.list(projectPath: sourceProjectPath)
            return worktrees.first { CanonicalPath.normalize($0.path) == workspace.primaryRoot }
        } catch {
            try finalizeOwnedTaskWorkspace(
                workspace,
                originalError: error,
                failure: TaskWorkspaceCleanupError.gitInspectionFailed,
                combinedFailure: TaskWorkspaceCleanupError.gitInspectionAndFallbackFailed
            )
            return nil
        }
    }

    func removeRegisteredTaskWorktree(
        _ workspace: TaskWorkspaceDescriptor,
        branch: String?,
        sourceProjectPath: String,
        sourceProjectIdentity: TaskWorkspaceFileSystemIdentity,
        worktreeIdentity: TaskWorkspaceFileSystemIdentity
    ) async throws {
        do {
            try await worktreeManager.remove(
                projectPath: sourceProjectPath,
                worktreePath: workspace.primaryRoot,
                branch: branch,
                expectedProjectIdentity: sourceProjectIdentity,
                expectedWorktreeIdentity: worktreeIdentity
            )
        } catch {
            try finalizeOwnedTaskWorkspace(
                workspace,
                originalError: error,
                failure: TaskWorkspaceCleanupError.gitRemovalFailed,
                combinedFailure: TaskWorkspaceCleanupError.gitRemovalAndFallbackFailed
            )
            return
        }
        try taskWorkspaceOwnershipService.removeOwnedWorkspace(workspace)
    }

    func finalizeOwnedTaskWorkspace(
        _ workspace: TaskWorkspaceDescriptor,
        originalError: Error,
        failure: (Error) -> TaskWorkspaceCleanupError,
        combinedFailure: (Error, Error) -> TaskWorkspaceCleanupError
    ) throws {
        do {
            try taskWorkspaceOwnershipService.removeOwnedWorkspace(workspace)
        } catch {
            throw combinedFailure(originalError, error)
        }
        throw failure(originalError)
    }
}

enum TaskWorkspaceCleanupError: LocalizedError {
    case pendingScheduledCleanupAlreadyInProgress
    case sourceProjectChanged(String)
    case pendingGitCleanupFailed(Error)
    case pendingGitAndFallbackFailed(gitError: Error, fallbackError: Error)
    case gitInspectionFailed(Error)
    case gitInspectionAndFallbackFailed(gitError: Error, fallbackError: Error)
    case gitRemovalFailed(Error)
    case gitRemovalAndFallbackFailed(gitError: Error, fallbackError: Error)
    case replacementDirectoryPreserved(Error)
    case replacementRecordCleanupFailed(identityError: Error, recordError: Error)

    var errorDescription: String? {
        switch self {
        case .pendingScheduledCleanupAlreadyInProgress:
            return "The Task's pending worktree cleanup is already in progress."
        case .sourceProjectChanged(let path):
            return "Git cleanup was deferred because the Task's source Project directory changed: \(path)"
        case .pendingGitCleanupFailed(let error):
            return "The owned Task workspace was removed, but its pending Git cleanup failed: \(error.localizedDescription)"
        case let .pendingGitAndFallbackFailed(gitError, fallbackError):
            return "Pending Git cleanup failed (\(gitError.localizedDescription)), and exact owned-workspace cleanup also failed: " +
                fallbackError.localizedDescription
        case .gitInspectionFailed(let error):
            return "The owned Task workspace was removed, but its Git worktree metadata could not be inspected: \(error.localizedDescription)"
        case let .gitInspectionAndFallbackFailed(gitError, fallbackError):
            return "Git worktree inspection failed (\(gitError.localizedDescription)), and exact owned-workspace cleanup also failed: " +
                fallbackError.localizedDescription
        case .gitRemovalFailed(let error):
            return "The owned Task workspace was removed, but its Git worktree cleanup failed: \(error.localizedDescription)"
        case let .gitRemovalAndFallbackFailed(gitError, fallbackError):
            return "Git worktree cleanup failed (\(gitError.localizedDescription)), and exact owned-workspace cleanup also failed: " +
                fallbackError.localizedDescription
        case .replacementDirectoryPreserved(let error):
            return error.localizedDescription
        case let .replacementRecordCleanupFailed(identityError, recordError):
            return "The replacement directory was preserved (\(identityError.localizedDescription)), but its stale ownership record " +
                "could not be removed: \(recordError.localizedDescription)"
        }
    }
}

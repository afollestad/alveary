import Foundation

extension SidebarViewModel {
    func cleanupTaskWorkspace(_ snapshot: ThreadCleanupSnapshot) async throws {
        guard let workspace = snapshot.taskWorkspace else {
            throw SidebarViewModelError.threadMissingTaskWorkspace
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
        guard directoryExists(at: sourceProjectPath) else {
            try taskWorkspaceOwnershipService.removeOwnedWorkspace(workspace)
            return
        }

        let isRegistered = try await taskWorktreeIsRegistered(workspace, sourceProjectPath: sourceProjectPath)
        guard isRegistered else {
            try taskWorkspaceOwnershipService.removeOwnedWorkspace(workspace)
            return
        }
        try await removeRegisteredTaskWorktree(workspace, snapshot: snapshot, sourceProjectPath: sourceProjectPath)
    }

    func taskWorktreeIsRegistered(
        _ workspace: TaskWorkspaceDescriptor,
        sourceProjectPath: String
    ) async throws -> Bool {
        do {
            let worktrees = try await worktreeManager.list(projectPath: sourceProjectPath)
            return worktrees.contains { CanonicalPath.normalize($0.path) == workspace.primaryRoot }
        } catch {
            try finalizeOwnedTaskWorkspace(
                workspace,
                originalError: error,
                failure: TaskWorkspaceCleanupError.gitInspectionFailed,
                combinedFailure: TaskWorkspaceCleanupError.gitInspectionAndFallbackFailed
            )
            return false
        }
    }

    func removeRegisteredTaskWorktree(
        _ workspace: TaskWorkspaceDescriptor,
        snapshot: ThreadCleanupSnapshot,
        sourceProjectPath: String
    ) async throws {
        do {
            try await worktreeManager.remove(
                projectPath: sourceProjectPath,
                worktreePath: workspace.primaryRoot,
                branch: snapshot.branch
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

private enum TaskWorkspaceCleanupError: LocalizedError {
    case gitInspectionFailed(Error)
    case gitInspectionAndFallbackFailed(gitError: Error, fallbackError: Error)
    case gitRemovalFailed(Error)
    case gitRemovalAndFallbackFailed(gitError: Error, fallbackError: Error)
    case replacementDirectoryPreserved(Error)
    case replacementRecordCleanupFailed(identityError: Error, recordError: Error)

    var errorDescription: String? {
        switch self {
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

import Foundation

enum ScheduledTurnWorkspaceValidationError: LocalizedError {
    case missingRun
    case missingWorkspace
    case workspaceDoesNotMatchRun
    case workspaceRootsChanged

    var errorDescription: String? {
        switch self {
        case .missingRun:
            return "The scheduled task is no longer linked to its run."
        case .missingWorkspace:
            return "The scheduled task workspace is unavailable."
        case .workspaceDoesNotMatchRun:
            return "The scheduled task workspace no longer matches its claimed configuration."
        case .workspaceRootsChanged:
            return "The scheduled task workspace or folder access changed after the run was prepared."
        }
    }
}

@MainActor
struct ScheduledTaskAutomatedWorkspaceValidator {
    let workspaceOwnershipService: any TaskWorkspaceOwnershipService

    func validate(thread: AgentThread) throws {
        guard let run = thread.scheduledTaskRun else {
            throw ScheduledTurnWorkspaceValidationError.missingRun
        }
        guard thread.mode == .task,
              let workspace = thread.taskWorkspaceDescriptor else {
            throw ScheduledTurnWorkspaceValidationError.missingWorkspace
        }
        guard workspace.primaryRoot == run.preparedWorkspaceRoot,
              workspace.ownershipStrategy == run.preparedWorkspaceOwnershipStrategy,
              workspace.ownershipMarkerID == run.preparedWorkspaceMarkerID else {
            throw ScheduledTurnWorkspaceValidationError.workspaceDoesNotMatchRun
        }
        guard let workspaceKind = run.workspaceKindSnapshot,
              run.workspaceStrategySnapshot != nil,
              let workspaceIdentities = run.workspaceIdentitySnapshot,
              workspaceIdentities.matchesConfiguration(
                  workspaceKind: workspaceKind,
                  projectPath: run.projectPathSnapshot,
                  grantedRootPaths: run.grantedRootsSnapshot
              ) else {
            throw ScheduledTurnWorkspaceValidationError.workspaceRootsChanged
        }

        try validateWorkspaceKind(workspace, run: run, workspaceIdentities: workspaceIdentities)
        try validateGrantedRoots(workspace, run: run, workspaceIdentities: workspaceIdentities)
    }
}

private extension ScheduledTaskAutomatedWorkspaceValidator {
    func validateWorkspaceKind(
        _ workspace: TaskWorkspaceDescriptor,
        run: ScheduledTaskRun,
        workspaceIdentities: ScheduledTaskWorkspaceIdentitySnapshot
    ) throws {
        guard let workspaceKind = run.workspaceKindSnapshot,
              let workspaceStrategy = run.workspaceStrategySnapshot else {
            throw ScheduledTurnWorkspaceValidationError.workspaceDoesNotMatchRun
        }
        switch (workspaceKind, workspaceStrategy) {
        case (.privateWorkspace, _):
            try validatePrivateWorkspace(workspace)
        case (.project, .localCheckout):
            try validateLocalProjectWorkspace(workspace, run: run, workspaceIdentities: workspaceIdentities)
        case (.project, .worktree):
            try validateProjectWorktree(workspace, run: run, workspaceIdentities: workspaceIdentities)
        }
    }

    func validatePrivateWorkspace(_ workspace: TaskWorkspaceDescriptor) throws {
        guard workspace.ownershipStrategy == .privateOwned else {
            throw ScheduledTurnWorkspaceValidationError.workspaceDoesNotMatchRun
        }
        try workspaceOwnershipService.validateOwnedWorkspace(workspace)
    }

    func validateLocalProjectWorkspace(
        _ workspace: TaskWorkspaceDescriptor,
        run: ScheduledTaskRun,
        workspaceIdentities: ScheduledTaskWorkspaceIdentitySnapshot
    ) throws {
        guard workspace.ownershipStrategy == .projectLocal,
              let projectPath = run.projectPathSnapshot else {
            throw ScheduledTurnWorkspaceValidationError.workspaceDoesNotMatchRun
        }
        guard workspace.primaryRoot == projectPath,
              workspace.sourceProjectPath == projectPath else {
            throw ScheduledTurnWorkspaceValidationError.workspaceRootsChanged
        }
        guard let claimedProjectIdentity = workspaceIdentities.projectRoot?.identity,
              currentIdentity(at: projectPath) == claimedProjectIdentity else {
            throw ScheduledTurnWorkspaceValidationError.workspaceRootsChanged
        }
        let canonicalRoots = try workspaceOwnershipService.canonicalizeGrants(
            [workspace.primaryRoot],
            excludingPrimaryRoot: nil
        )
        guard canonicalRoots == [projectPath] else {
            throw ScheduledTurnWorkspaceValidationError.workspaceRootsChanged
        }
    }

    func validateProjectWorktree(
        _ workspace: TaskWorkspaceDescriptor,
        run: ScheduledTaskRun,
        workspaceIdentities: ScheduledTaskWorkspaceIdentitySnapshot
    ) throws {
        guard workspace.ownershipStrategy == .projectWorktreeOwned,
              let projectPath = run.projectPathSnapshot else {
            throw ScheduledTurnWorkspaceValidationError.workspaceDoesNotMatchRun
        }
        guard workspace.sourceProjectPath == projectPath,
              CanonicalPath.normalize(projectPath) == projectPath else {
            throw ScheduledTurnWorkspaceValidationError.workspaceRootsChanged
        }
        try workspaceOwnershipService.validateOwnedWorkspace(workspace)
        guard let claimedProjectIdentity = workspaceIdentities.projectRoot?.identity,
              let registeredSourceIdentity = try workspaceOwnershipService.sourceProjectIdentity(
            forOwnedWorktree: workspace
        ),
            registeredSourceIdentity == claimedProjectIdentity,
            currentIdentity(at: projectPath) == claimedProjectIdentity else {
            throw ScheduledTurnWorkspaceValidationError.workspaceRootsChanged
        }
    }

    func validateGrantedRoots(
        _ workspace: TaskWorkspaceDescriptor,
        run: ScheduledTaskRun,
        workspaceIdentities: ScheduledTaskWorkspaceIdentitySnapshot
    ) throws {
        guard workspace.grantedRoots == run.grantedRootsSnapshot else {
            throw ScheduledTurnWorkspaceValidationError.workspaceRootsChanged
        }
        let canonicalGrants = try workspaceOwnershipService.canonicalizeGrants(
            workspace.grantedRoots,
            excludingPrimaryRoot: workspace.primaryRoot
        )
        guard canonicalGrants == run.grantedRootsSnapshot else {
            throw ScheduledTurnWorkspaceValidationError.workspaceRootsChanged
        }
        for claimedGrant in workspaceIdentities.grantedRoots {
            guard currentIdentity(at: claimedGrant.path) == claimedGrant.identity else {
                throw ScheduledTurnWorkspaceValidationError.workspaceRootsChanged
            }
        }
    }

    func currentIdentity(at path: String) -> TaskWorkspaceFileSystemIdentity? {
        try? workspaceOwnershipService.directoryIdentity(at: path)
    }
}

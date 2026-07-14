import Foundation
import SwiftData

extension DefaultScheduledTaskRunMaterializer {
    func prepareWorkspaceOrPersistFailure(
        runID: PersistentIdentifier,
        snapshot: ScheduledTaskRunSnapshot
    ) async throws -> PreparedScheduledTaskWorkspace {
        do {
            return try await prepareWorkspace(for: snapshot, runID: runID)
        } catch is CancellationError {
            throw CancellationError()
        } catch let preparationError {
            try markTaskShellFailedWithRetry(runID: runID, error: preparationError)
            throw preparationError
        }
    }

    func prepareWorkspace(
        for snapshot: ScheduledTaskRunSnapshot,
        runID: PersistentIdentifier
    ) async throws -> PreparedScheduledTaskWorkspace {
        guard let workspaceIdentities = snapshot.workspaceIdentities else {
            throw ScheduledTaskRunMaterializationError.missingWorkspaceIdentityProvenance
        }
        guard workspaceIdentities.matchesConfiguration(
            workspaceKind: snapshot.workspaceKind,
            projectPath: snapshot.projectPath,
            grantedRootPaths: snapshot.grantedRoots
        ) else {
            throw ScheduledTaskRunMaterializationError.workspaceRootsChanged
        }

        switch snapshot.workspaceKind {
        case .privateWorkspace:
            return try preparePrivateWorkspace(
                grantedRoots: snapshot.grantedRoots,
                workspaceIdentities: workspaceIdentities,
                runID: runID
            )
        case .project:
            guard let projectPath = snapshot.projectPath else {
                throw ScheduledTaskRunMaterializationError.missingProjectPath
            }
            switch snapshot.workspaceStrategy {
            case .localCheckout:
                return try prepareProjectLocalWorkspace(
                    projectPath: projectPath,
                    grantedRoots: snapshot.grantedRoots,
                    workspaceIdentities: workspaceIdentities
                )
            case .worktree:
                return try await prepareProjectWorktree(
                    runID: runID,
                    snapshot: snapshot,
                    workspaceIdentities: workspaceIdentities
                )
            }
        }
    }

    func preparePrivateWorkspace(
        grantedRoots: [String],
        workspaceIdentities: ScheduledTaskWorkspaceIdentitySnapshot,
        runID: PersistentIdentifier
    ) throws -> PreparedScheduledTaskWorkspace {
        let ownedWorkspace = try workspaceOwnershipService.createPrivateWorkspace()
        do {
            let canonicalGrants = try workspaceOwnershipService.canonicalizeGrants(
                grantedRoots,
                excludingPrimaryRoot: ownedWorkspace.primaryRoot
            )
            try requireSnapshotRoots(canonicalGrants, equal: grantedRoots)
            try requireCurrentWorkspaceIdentities(workspaceIdentities)
            let workspace = TaskWorkspaceDescriptor(
                primaryRoot: ownedWorkspace.primaryRoot,
                grantedRoots: canonicalGrants,
                ownershipStrategy: ownedWorkspace.ownershipStrategy,
                ownershipMarkerID: ownedWorkspace.ownershipMarkerID
            )
            return PreparedScheduledTaskWorkspace(
                descriptor: workspace,
                branch: nil,
                branchOID: nil,
                sourceProjectIdentity: nil
            )
        } catch {
            do {
                try workspaceOwnershipService.removeOwnedWorkspace(ownedWorkspace)
            } catch let cleanupError {
                try retainPreparedWorkspaceMetadata(
                    PreparedScheduledTaskWorkspace(
                        descriptor: ownedWorkspace,
                        branch: nil,
                        branchOID: nil,
                        sourceProjectIdentity: nil
                    ),
                    runID: runID
                )
                throw ScheduledTaskRunMaterializationError.preparationAndCleanupFailed(
                    preparation: error,
                    cleanup: cleanupError
                )
            }
            throw error
        }
    }

    func prepareProjectLocalWorkspace(
        projectPath: String,
        grantedRoots: [String],
        workspaceIdentities: ScheduledTaskWorkspaceIdentitySnapshot
    ) throws -> PreparedScheduledTaskWorkspace {
        let roots = try workspaceOwnershipService.canonicalizeGrants(
            [projectPath],
            excludingPrimaryRoot: nil
        )
        guard let canonicalProjectPath = roots.first else {
            throw ScheduledTaskRunMaterializationError.projectWorkspaceMissing(projectPath)
        }
        try requireSnapshotRoots(roots, equal: [projectPath])
        let canonicalGrants = try workspaceOwnershipService.canonicalizeGrants(
            grantedRoots,
            excludingPrimaryRoot: canonicalProjectPath
        )
        try requireSnapshotRoots(canonicalGrants, equal: grantedRoots)
        try requireCurrentWorkspaceIdentities(workspaceIdentities)
        let workspace = TaskWorkspaceDescriptor(
            primaryRoot: canonicalProjectPath,
            grantedRoots: canonicalGrants,
            ownershipStrategy: .projectLocal,
            sourceProjectPath: canonicalProjectPath
        )
        return PreparedScheduledTaskWorkspace(
            descriptor: workspace,
            branch: nil,
            branchOID: nil,
            sourceProjectIdentity: nil
        )
    }

    func prepareProjectWorktree(
        runID: PersistentIdentifier,
        snapshot: ScheduledTaskRunSnapshot,
        workspaceIdentities: ScheduledTaskWorkspaceIdentitySnapshot
    ) async throws -> PreparedScheduledTaskWorkspace {
        guard let projectPath = snapshot.projectPath else {
            throw ScheduledTaskRunMaterializationError.missingProjectPath
        }
        guard let sourceProjectIdentity = workspaceIdentities.projectRoot?.identity else {
            throw ScheduledTaskRunMaterializationError.missingWorkspaceIdentityProvenance
        }
        let roots = try workspaceOwnershipService.canonicalizeGrants(
            [projectPath],
            excludingPrimaryRoot: nil
        )
        guard let canonicalProjectPath = roots.first else {
            throw ScheduledTaskRunMaterializationError.projectWorkspaceMissing(projectPath)
        }
        try requireSnapshotRoots(roots, equal: [projectPath])
        let canonicalGrants = try workspaceOwnershipService.canonicalizeGrants(
            snapshot.grantedRoots,
            excludingPrimaryRoot: canonicalProjectPath
        )
        try requireSnapshotRoots(canonicalGrants, equal: snapshot.grantedRoots)
        try requireCurrentWorkspaceIdentities(workspaceIdentities)
        return try await createAndRegisterProjectWorktree(
            runID: runID,
            configuration: PreparedProjectWorktreeConfiguration(
                snapshot: snapshot,
                canonicalProjectPath: canonicalProjectPath,
                canonicalGrants: canonicalGrants,
                sourceProjectIdentity: sourceProjectIdentity,
                workspaceIdentities: workspaceIdentities
            )
        )
    }

    func createAndRegisterProjectWorktree(
        runID: PersistentIdentifier,
        configuration: PreparedProjectWorktreeConfiguration
    ) async throws -> PreparedScheduledTaskWorkspace {
        let snapshot = configuration.snapshot
        let projectPath = configuration.canonicalProjectPath
        let sourceIdentity = configuration.sourceProjectIdentity
        let ownershipMarkerID = UUID().uuidString.lowercased()
        let createdWorktree = try await createWorktree(
            runID: runID,
            configuration: configuration,
            ownershipMarkerID: ownershipMarkerID
        )
        let info = createdWorktree.info

        var registeredWorkspace: TaskWorkspaceDescriptor?
        do {
            let workspace = try registerProjectWorktree(
                createdWorktree,
                configuration: configuration,
                ownershipMarkerID: ownershipMarkerID
            )
            registeredWorkspace = workspace
            try validatePreparedWorktree(
                workspace,
                sourceProjectPath: projectPath,
                sourceProjectIdentity: sourceIdentity,
                snapshotGrants: snapshot.grantedRoots,
                workspaceIdentities: configuration.workspaceIdentities
            )
            return PreparedScheduledTaskWorkspace(
                descriptor: workspace,
                branch: info.branch,
                branchOID: info.headOID,
                sourceProjectIdentity: sourceIdentity
            )
        } catch {
            do {
                try await cleanupFailedWorktreePreparation(
                    runID: runID,
                    registeredWorkspace: registeredWorkspace,
                    projectPath: projectPath,
                    createdWorktree: createdWorktree,
                    ownershipMarkerID: ownershipMarkerID
                )
            } catch let cleanupError {
                throw ScheduledTaskRunMaterializationError.preparationAndCleanupFailed(
                    preparation: error,
                    cleanup: cleanupError
                )
            }
            throw error
        }
    }

    func registerProjectWorktree(
        _ createdWorktree: IdentityValidatedWorktreeInfo,
        configuration: PreparedProjectWorktreeConfiguration,
        ownershipMarkerID: String
    ) throws -> TaskWorkspaceDescriptor {
        try workspaceOwnershipService.registerOwnedWorktree(
            at: createdWorktree.info.path,
            sourceProjectPath: configuration.canonicalProjectPath,
            grantedRoots: configuration.canonicalGrants,
            registrationProvenance: WorktreeRegistrationProvenance(
                ownershipMarkerID: ownershipMarkerID,
                expectedWorktreeIdentity: createdWorktree.worktreeIdentity,
                expectedSourceProjectIdentity: createdWorktree.sourceProjectIdentity
            )
        )
    }

    func validatePreparedWorktree(
        _ workspace: TaskWorkspaceDescriptor,
        sourceProjectPath: String,
        sourceProjectIdentity: TaskWorkspaceFileSystemIdentity,
        snapshotGrants: [String],
        workspaceIdentities: ScheduledTaskWorkspaceIdentitySnapshot
    ) throws {
        try Task.checkCancellation()
        guard workspace.sourceProjectPath == sourceProjectPath,
              sourceProjectIdentityIsCurrent(
                  at: sourceProjectPath,
                  expected: sourceProjectIdentity
              ) else {
            throw ScheduledTaskRunMaterializationError.workspaceRootsChanged
        }
        try workspaceOwnershipService.validateOwnedWorkspace(workspace)
        let registeredSourceIdentity = try workspaceOwnershipService.sourceProjectIdentity(
            forOwnedWorktree: workspace
        )
        guard registeredSourceIdentity == sourceProjectIdentity else {
            throw ScheduledTaskRunMaterializationError.workspaceRootsChanged
        }
        try requireSnapshotRoots(workspace.grantedRoots, equal: snapshotGrants)
        try requireCurrentWorkspaceIdentities(workspaceIdentities)
    }

    func createWorktree(
        runID: PersistentIdentifier,
        configuration: PreparedProjectWorktreeConfiguration,
        ownershipMarkerID: String
    ) async throws -> IdentityValidatedWorktreeInfo {
        do {
            return try await worktreeManager.create(
                projectPath: configuration.canonicalProjectPath,
                threadName: configuration.snapshot.title,
                baseRef: configuration.snapshot.projectBaseRef,
                remoteName: configuration.snapshot.projectRemoteName,
                provenanceContext: WorktreeCreationProvenanceContext(
                    expectedProjectIdentity: configuration.sourceProjectIdentity,
                    recorder: { [weak self] cleanup in
                        guard let self else {
                            throw ScheduledTaskRunMaterializationError.runChangedDuringPreparation
                        }
                        try self.persistFailedCreationCleanup(
                            cleanup,
                            runID: runID,
                            ownershipMarkerID: ownershipMarkerID,
                            ownershipSourceProjectPath: configuration.canonicalProjectPath
                        )
                    }
                )
            )
        } catch let rollbackError as WorktreeCreationRollbackError {
            try persistFailedCreationCleanup(
                rollbackError.cleanup,
                runID: runID,
                ownershipMarkerID: ownershipMarkerID,
                ownershipSourceProjectPath: configuration.canonicalProjectPath
            )
            throw rollbackError
        }
    }

    func persistFailedCreationCleanup(
        _ cleanup: FailedWorktreeCreationCleanup,
        runID: PersistentIdentifier,
        ownershipMarkerID: String? = nil,
        ownershipSourceProjectPath: String? = nil
    ) throws {
        guard let provenance = ScheduledWorktreeCleanupProvenance(
            sourceProjectPath: cleanup.sourceProjectPath,
            worktreePath: cleanup.worktreePath,
            branch: cleanup.branch,
            sourceProjectIdentity: cleanup.sourceProjectIdentity,
            worktreeIdentity: cleanup.worktreeIdentity,
            branchIsOwned: cleanup.branchIsOwned,
            branchOID: cleanup.branchOID,
            ownershipMarkerID: ownershipMarkerID,
            ownershipSourceProjectPath: ownershipSourceProjectPath
        ) else {
            throw ScheduledTaskRunMaterializationError.missingWorktreeCleanupMetadata
        }
        try persistPendingWorktreeCleanup(
            provenance,
            runID: runID,
            replacesBranchOID: cleanup.branchOID != nil
        )
    }
}

struct PreparedProjectWorktreeConfiguration {
    let snapshot: ScheduledTaskRunSnapshot
    let canonicalProjectPath: String
    let canonicalGrants: [String]
    let sourceProjectIdentity: TaskWorkspaceFileSystemIdentity
    let workspaceIdentities: ScheduledTaskWorkspaceIdentitySnapshot
}

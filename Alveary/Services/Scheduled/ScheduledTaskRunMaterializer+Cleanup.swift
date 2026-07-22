import Foundation
import SwiftData

extension DefaultScheduledTaskRunMaterializer {
    func handlePreparedWorkspaceFailure(
        _ preparationError: Error,
        preparedWorkspace: PreparedScheduledTaskWorkspace,
        runID: PersistentIdentifier,
        wasCancelled: Bool
    ) async throws -> Never {
        var cleanupFailed = false
        let surfacedError: Error
        do {
            try await cleanup(preparedWorkspace, runID: runID)
            try clearPreparedWorkspaceMetadata(runID: runID)
            surfacedError = preparationError
        } catch let cleanupError {
            cleanupFailed = true
            if preparedWorkspace.descriptor.ownershipStrategy == .privateOwned {
                try retainPreparedWorkspaceMetadata(preparedWorkspace, runID: runID)
            } else {
                try clearPreparedWorkspaceMetadata(runID: runID)
            }
            surfacedError = ScheduledTaskRunMaterializationError.preparationAndCleanupFailed(
                preparation: preparationError,
                cleanup: cleanupError
            )
        }
        if wasCancelled, !cleanupFailed {
            throw CancellationError()
        }
        try markTaskShellFailedWithRetry(runID: runID, error: surfacedError)
        throw surfacedError
    }

    func retainPreparedWorkspaceMetadata(
        _ preparedWorkspace: PreparedScheduledTaskWorkspace,
        runID: PersistentIdentifier
    ) throws {
        guard let run = modelContext.resolveScheduledTaskRun(id: runID),
              run.status == .preparing,
              let thread = run.thread else {
            throw ScheduledTaskRunMaterializationError.runChangedDuringPreparation
        }
        applyPreparedWorkspaceMetadata(preparedWorkspace, run: run, thread: thread)
    }

    func clearPreparedWorkspaceMetadata(runID: PersistentIdentifier) throws {
        guard let run = modelContext.resolveScheduledTaskRun(id: runID),
              run.status == .preparing,
              let thread = run.thread else {
            throw ScheduledTaskRunMaterializationError.runChangedDuringPreparation
        }
        thread.branch = nil
        thread.worktreePath = nil
        thread.useWorktree = false
        thread.taskWorkspaceDescriptor = nil
        run.preparedWorkspaceRoot = nil
        run.preparedWorkspaceOwnershipStrategy = nil
        run.preparedWorkspaceMarkerID = nil
        run.workspaceCleanupProvenance = nil
    }

    func applyPreparedWorkspaceMetadata(
        _ preparedWorkspace: PreparedScheduledTaskWorkspace,
        run: ScheduledTaskRun,
        thread: AgentThread
    ) {
        let workspace = preparedWorkspace.descriptor
        thread.branch = preparedWorkspace.branch
        thread.worktreePath = workspace.ownershipStrategy == .projectWorktreeOwned ? workspace.primaryRoot : nil
        thread.useWorktree = workspace.ownershipStrategy == .projectWorktreeOwned
        if thread.mode == .task {
            thread.taskWorkspaceDescriptor = workspace
        } else if workspace.ownershipStrategy == .projectWorktreeOwned {
            // Project-mode scheduled threads still need the owned-worktree marker
            // for identity-safe cleanup without changing where they are presented.
            thread.taskWorkspaceDescriptor = workspace
        } else {
            thread.taskGrantedRoots = workspace.grantedRoots
        }
        run.preparedWorkspaceRoot = workspace.primaryRoot
        run.preparedWorkspaceOwnershipStrategy = workspace.ownershipStrategy
        run.preparedWorkspaceMarkerID = workspace.ownershipMarkerID
    }

    func cleanupFailedWorktreePreparation(
        runID: PersistentIdentifier,
        registeredWorkspace: TaskWorkspaceDescriptor?,
        projectPath: String,
        createdWorktree: IdentityValidatedWorktreeInfo,
        ownershipMarkerID: String
    ) async throws {
        let info = createdWorktree.info
        let worktreePath = registeredWorkspace?.primaryRoot ?? info.path
        let registeredWorktreeIdentity = registeredWorkspace.flatMap {
            try? workspaceOwnershipService.ownedWorktreeIdentity(for: $0)
        } ?? createdWorktree.worktreeIdentity
        guard let provenance = ScheduledWorktreeCleanupProvenance(
            sourceProjectPath: projectPath,
            worktreePath: worktreePath,
            branch: info.branch,
            sourceProjectIdentity: createdWorktree.sourceProjectIdentity,
            worktreeIdentity: registeredWorktreeIdentity,
            branchIsOwned: true,
            branchOID: info.headOID,
            ownershipMarkerID: registeredWorkspace?.ownershipMarkerID ?? ownershipMarkerID,
            ownershipSourceProjectPath: registeredWorkspace?.sourceProjectPath ?? projectPath
        ) else {
            throw ScheduledTaskRunMaterializationError.missingWorktreeCleanupMetadata
        }
        try await cleanupWorktree(
            runID: runID,
            provenance: provenance,
            registeredWorkspace: registeredWorkspace
        )
    }

    func cleanup(
        _ preparedWorkspace: PreparedScheduledTaskWorkspace,
        runID: PersistentIdentifier
    ) async throws {
        let workspace = preparedWorkspace.descriptor
        switch workspace.ownershipStrategy {
        case .privateOwned:
            try workspaceOwnershipService.removeOwnedWorkspace(workspace)
        case .projectLocal:
            break
        case .projectWorktreeOwned:
            guard let sourceProjectPath = workspace.sourceProjectPath,
                  let branch = preparedWorkspace.branch,
                  let sourceProjectIdentity = preparedWorkspace.sourceProjectIdentity else {
                throw ScheduledTaskRunMaterializationError.missingProjectPath
            }
            guard let provenance = ScheduledWorktreeCleanupProvenance(
                sourceProjectPath: sourceProjectPath,
                worktreePath: workspace.primaryRoot,
                branch: branch,
                sourceProjectIdentity: sourceProjectIdentity,
                worktreeIdentity: try workspaceOwnershipService.ownedWorktreeIdentity(for: workspace),
                branchIsOwned: true,
                branchOID: preparedWorkspace.branchOID,
                ownershipMarkerID: workspace.ownershipMarkerID,
                ownershipSourceProjectPath: workspace.sourceProjectPath
            ) else {
                throw ScheduledTaskRunMaterializationError.missingWorktreeCleanupMetadata
            }
            try await cleanupWorktree(
                runID: runID,
                provenance: provenance,
                registeredWorkspace: workspace
            )
        }
    }

    func cleanupWorktree(
        runID: PersistentIdentifier,
        provenance: ScheduledWorktreeCleanupProvenance,
        registeredWorkspace: TaskWorkspaceDescriptor?
    ) async throws {
        let durableProvenance = try persistPendingWorktreeCleanup(provenance, runID: runID)
        let cleanupWorkspace = registeredWorkspace ?? durableProvenance.ownedWorkspaceDescriptor
        try requireCurrentCleanupSource(durableProvenance, cleanupWorkspace: cleanupWorkspace, runID: runID)
        let branchProvenance = try await persistRegisteredBranchOIDIfProven(
            durableProvenance,
            cleanupWorkspace: cleanupWorkspace,
            runID: runID
        )
        try requireCurrentCleanupSource(branchProvenance, cleanupWorkspace: cleanupWorkspace, runID: runID)
        try await removePendingGitWorktree(branchProvenance, cleanupWorkspace: cleanupWorkspace, runID: runID)
        let branchCleanupError = try await deleteBranchAndRetireIfProven(
            branchProvenance,
            runID: runID
        )
        if let cleanupWorkspace {
            try removePendingOwnedWorkspace(
                cleanupWorkspace,
                expectedWorktreeIdentity: branchProvenance.worktreeIdentity,
                runID: runID
            )
        }
        if let branchCleanupError {
            throw branchCleanupError
        }
        try clearPendingWorktreeCleanup(runID: runID)
    }

    func requireCurrentCleanupSource(
        _ provenance: ScheduledWorktreeCleanupProvenance,
        cleanupWorkspace: TaskWorkspaceDescriptor?,
        runID: PersistentIdentifier
    ) throws {
        guard sourceProjectIdentityIsCurrent(
            at: provenance.sourceProjectPath,
            expected: provenance.sourceProjectIdentity
        ) else {
            if let cleanupWorkspace {
                try removePendingOwnedWorkspace(
                    cleanupWorkspace,
                    expectedWorktreeIdentity: provenance.worktreeIdentity,
                    runID: runID
                )
            }
            throw ScheduledTaskRunMaterializationError.worktreeCleanupSourceChanged(provenance.sourceProjectPath)
        }
    }

    func persistRegisteredBranchOIDIfProven(
        _ provenance: ScheduledWorktreeCleanupProvenance,
        cleanupWorkspace: TaskWorkspaceDescriptor?,
        runID: PersistentIdentifier
    ) async throws -> ScheduledWorktreeCleanupProvenance {
        guard provenance.branchIsOwned else {
            return provenance
        }
        guard let worktrees = try? await worktreeManager.list(projectPath: provenance.sourceProjectPath) else {
            return provenance
        }
        try requireCurrentCleanupSource(
            provenance,
            cleanupWorkspace: cleanupWorkspace,
            runID: runID
        )
        guard cleanupWorktreeIdentityIsCurrent(provenance) else {
            return provenance
        }
        guard let headOID = worktrees.first(where: {
            CanonicalPath.normalize($0.path) == provenance.worktreePath &&
                $0.branch == provenance.branch
        })?.headOID else {
            return provenance
        }
        let updatedProvenance = provenance.recordingBranchOID(headOID)
        guard updatedProvenance != provenance else {
            return provenance
        }
        return try persistPendingWorktreeCleanup(
            updatedProvenance,
            runID: runID,
            replacesBranchOID: true
        )
    }

    func removePendingGitWorktree(
        _ provenance: ScheduledWorktreeCleanupProvenance,
        cleanupWorkspace: TaskWorkspaceDescriptor?,
        runID: PersistentIdentifier
    ) async throws {
        do {
            try await worktreeManager.remove(
                projectPath: provenance.sourceProjectPath,
                worktreePath: provenance.worktreePath,
                branch: nil,
                expectedProjectIdentity: provenance.sourceProjectIdentity,
                expectedWorktreeIdentity: provenance.worktreeIdentity
            )
        } catch {
            if let cleanupWorkspace {
                try removePendingOwnedWorkspace(
                    cleanupWorkspace,
                    expectedWorktreeIdentity: provenance.worktreeIdentity,
                    runID: runID
                )
            }
            throw error
        }
    }

    func deleteBranchAndRetireIfProven(
        _ provenance: ScheduledWorktreeCleanupProvenance,
        runID: PersistentIdentifier
    ) async throws -> Error? {
        let branchOwnershipWasRetired = try retirePendingWorktreeBranchOwnership(provenance, runID: runID)
        guard branchOwnershipWasRetired, let expectedOID = provenance.branchOID else {
            return nil
        }
        do {
            try await worktreeManager.deleteBranch(
                projectPath: provenance.sourceProjectPath,
                branch: provenance.branch,
                expectedOID: expectedOID,
                expectedProjectIdentity: provenance.sourceProjectIdentity
            )
        } catch let error as RetryableWorktreeBranchDeletionError {
            try restorePendingWorktreeBranchOwnership(provenance, runID: runID)
            return error
        } catch {
            return error
        }
        return nil
    }

    @discardableResult
    func persistPendingWorktreeCleanup(
        _ provenance: ScheduledWorktreeCleanupProvenance,
        runID: PersistentIdentifier,
        replacesBranchOID: Bool = false
    ) throws -> ScheduledWorktreeCleanupProvenance {
        guard let run = modelContext.resolveScheduledTaskRun(id: runID),
              run.status == .preparing else {
            throw ScheduledTaskRunMaterializationError.runChangedDuringPreparation
        }
        let durableProvenance: ScheduledWorktreeCleanupProvenance
        if let currentProvenance = run.pendingWorktreeCleanup,
           currentProvenance.identifiesSameBranchCleanup(as: provenance) {
            durableProvenance = currentProvenance.mergingDurableProof(
                from: provenance,
                replacesBranchOID: replacesBranchOID
            )
        } else {
            durableProvenance = provenance
        }
        run.setPendingWorktreeCleanup(durableProvenance)
        try persistCleanupProvenance()
        return durableProvenance
    }

    func retirePendingWorktreeBranchOwnership(
        _ provenance: ScheduledWorktreeCleanupProvenance,
        runID: PersistentIdentifier
    ) throws -> Bool {
        guard let run = modelContext.resolveScheduledTaskRun(id: runID),
              run.status == .preparing,
              let currentCleanup = run.pendingWorktreeCleanup,
              currentCleanup.identifiesSameBranchCleanup(as: provenance) else {
            throw ScheduledTaskRunMaterializationError.runChangedDuringPreparation
        }
        guard currentCleanup.branchIsOwned else {
            return false
        }
        run.pendingWorktreeCleanupBranchIsOwned = false
        do {
            try persistCleanupProvenance()
        } catch {
            run.pendingWorktreeCleanupBranchIsOwned = true
            throw error
        }
        return true
    }

    func restorePendingWorktreeBranchOwnership(
        _ provenance: ScheduledWorktreeCleanupProvenance,
        runID: PersistentIdentifier
    ) throws {
        guard let run = modelContext.resolveScheduledTaskRun(id: runID),
              run.status == .preparing,
              let currentCleanup = run.pendingWorktreeCleanup,
              currentCleanup.identifiesSameBranchCleanup(as: provenance),
              !currentCleanup.branchIsOwned else {
            throw ScheduledTaskRunMaterializationError.runChangedDuringPreparation
        }
        run.pendingWorktreeCleanupBranchIsOwned = true
        do {
            try persistCleanupProvenance()
        } catch {
            run.pendingWorktreeCleanupBranchIsOwned = false
            throw error
        }
    }

    func removePendingOwnedWorkspace(
        _ workspace: TaskWorkspaceDescriptor,
        expectedWorktreeIdentity: TaskWorkspaceFileSystemIdentity?,
        runID: PersistentIdentifier
    ) throws {
        try workspaceOwnershipService.removeProvisionalOwnedWorktree(
            workspace,
            expectedWorktreeIdentity: expectedWorktreeIdentity
        )
        guard let run = modelContext.resolveScheduledTaskRun(id: runID),
              run.status == .preparing else {
            throw ScheduledTaskRunMaterializationError.runChangedDuringPreparation
        }
        run.clearPendingWorktreeOwnershipCleanup()
        try persistCleanupProvenance()
    }

    func clearPendingWorktreeCleanup(runID: PersistentIdentifier) throws {
        guard let run = modelContext.resolveScheduledTaskRun(id: runID),
              run.status == .preparing else {
            throw ScheduledTaskRunMaterializationError.runChangedDuringPreparation
        }
        run.clearPendingWorktreeCleanup()
        try persistCleanupProvenance()
    }

    func persistCleanupProvenance() throws {
        var persistenceError: Error?
        for _ in 0..<provenancePersistenceAttempts {
            do {
                try saveChanges(modelContext)
                return
            } catch {
                persistenceError = error
            }
        }
        throw ScheduledTaskRunMaterializationError.provenancePersistenceFailed(
            persistenceError ?? ScheduledTaskRunMaterializationError.runChangedDuringPreparation
        )
    }

    func sourceProjectIdentityIsCurrent(
        at sourceProjectPath: String,
        expected: TaskWorkspaceFileSystemIdentity
    ) -> Bool {
        guard CanonicalPath.normalize(sourceProjectPath) == sourceProjectPath else {
            return false
        }
        guard let current = try? workspaceOwnershipService.directoryIdentity(at: sourceProjectPath) else {
            return false
        }
        return current == expected
    }

    func cleanupWorktreeIdentityIsCurrent(
        _ provenance: ScheduledWorktreeCleanupProvenance
    ) -> Bool {
        guard let expectedIdentity = provenance.worktreeIdentity,
              CanonicalPath.normalize(provenance.worktreePath) == provenance.worktreePath,
              let currentIdentity = try? workspaceOwnershipService.directoryIdentity(
                  at: provenance.worktreePath
              ) else {
            return false
        }
        return currentIdentity == expectedIdentity
    }
}

private extension ScheduledWorktreeCleanupProvenance {
    func identifiesSameBranchCleanup(as other: ScheduledWorktreeCleanupProvenance) -> Bool {
        sourceProjectPath == other.sourceProjectPath &&
            worktreePath == other.worktreePath &&
            branch == other.branch &&
            sourceProjectIdentity == other.sourceProjectIdentity
    }

    func mergingDurableProof(
        from newer: ScheduledWorktreeCleanupProvenance,
        replacesBranchOID: Bool
    ) -> ScheduledWorktreeCleanupProvenance {
        let mergedWorktreeIdentity = worktreeIdentity ?? newer.worktreeIdentity
        let mergedOwnershipMarkerID: String?
        let mergedOwnershipSourceProjectPath: String?
        if ownershipMarkerID == nil, ownershipSourceProjectPath == nil {
            mergedOwnershipMarkerID = newer.ownershipMarkerID
            mergedOwnershipSourceProjectPath = newer.ownershipSourceProjectPath
        } else {
            mergedOwnershipMarkerID = ownershipMarkerID
            mergedOwnershipSourceProjectPath = ownershipSourceProjectPath
        }

        var mergedBranchIsOwned = branchIsOwned
        var mergedBranchOID = branchOID
        if branchIsOwned {
            if newer.branchIsOwned,
               let newerBranchOID = newer.branchOID,
               replacesBranchOID || branchOID == nil {
                mergedBranchOID = newerBranchOID
            }
        } else if branchOID == nil,
                  newer.branchIsOwned,
                  let newerBranchOID = newer.branchOID {
            // A false ownership bit with an OID is a durable retirement fence. Only the
            // pre-retirement creation sequence may advance from unowned to owned.
            mergedBranchIsOwned = true
            mergedBranchOID = newerBranchOID
        }

        return ScheduledWorktreeCleanupProvenance(
            sourceProjectPath: sourceProjectPath,
            worktreePath: worktreePath,
            branch: branch,
            sourceProjectIdentity: sourceProjectIdentity,
            worktreeIdentity: mergedWorktreeIdentity,
            branchIsOwned: mergedBranchIsOwned,
            branchOID: mergedBranchOID,
            ownershipMarkerID: mergedOwnershipMarkerID,
            ownershipSourceProjectPath: mergedOwnershipSourceProjectPath
        ) ?? self
    }
}

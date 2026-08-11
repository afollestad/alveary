import Foundation

extension ScheduledTaskRun {
    var workspaceCleanupProvenance: ScheduledWorktreeCleanupProvenance? {
        get {
            guard let workspaceCleanupProvenanceJSON,
                  let data = workspaceCleanupProvenanceJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(ScheduledWorktreeCleanupProvenance.self, from: data) else {
                return nil
            }
            return ScheduledWorktreeCleanupProvenance(
                sourceProjectPath: decoded.sourceProjectPath,
                worktreePath: decoded.worktreePath,
                branch: decoded.branch,
                sourceProjectIdentity: decoded.sourceProjectIdentity,
                worktreeIdentity: decoded.worktreeIdentity,
                branchIsOwned: decoded.branchIsOwned,
                branchOID: decoded.branchOID,
                ownershipMarkerID: decoded.ownershipMarkerID,
                ownershipSourceProjectPath: decoded.ownershipSourceProjectPath
            )
        }
        set {
            workspaceCleanupProvenanceJSON = Self.encodeWorkspaceCleanupProvenance(newValue)
        }
    }

    var pendingWorktreeCleanup: ScheduledWorktreeCleanupProvenance? {
        ScheduledWorktreeCleanupProvenance(
            sourceProjectPath: pendingWorktreeCleanupSourceProjectPath,
            worktreePath: pendingWorktreeCleanupPath,
            branch: pendingWorktreeCleanupBranch,
            sourceProjectIdentitySystemNumber: pendingCleanupSourceIdentitySystemNumber,
            sourceProjectIdentityFileNumber: pendingCleanupSourceIdentityFileNumber,
            worktreeIdentitySystemNumber: pendingCleanupWorktreeSystemNumber,
            worktreeIdentityFileNumber: pendingCleanupWorktreeFileNumber,
            branchIsOwned: pendingWorktreeCleanupBranchIsOwned,
            branchOID: pendingWorktreeCleanupBranchOID,
            ownershipMarkerID: pendingWorktreeCleanupOwnershipMarkerID,
            ownershipSourceProjectPath: pendingCleanupOwnershipSourceProjectPath
        )
    }

    var workspaceIdentitySnapshot: ScheduledTaskWorkspaceIdentitySnapshot? {
        get {
            guard let workspaceIdentitySnapshotJSON,
                  let data = workspaceIdentitySnapshotJSON.data(using: .utf8) else {
                return nil
            }
            return try? JSONDecoder().decode(ScheduledTaskWorkspaceIdentitySnapshot.self, from: data)
        }
        set {
            workspaceIdentitySnapshotJSON = Self.encodeWorkspaceIdentitySnapshot(newValue)
        }
    }

    var hasValidWorkspaceIdentityProvenance: Bool {
        guard let workspaceKindSnapshot,
              workspaceStrategySnapshot != nil,
              let workspaceIdentitySnapshot else {
            return false
        }
        return workspaceIdentitySnapshot.matchesConfiguration(
            workspaceKind: workspaceKindSnapshot,
            projectPath: projectPathSnapshot,
            grantedRootPaths: grantedRootsSnapshot
        )
    }

    var hasPendingWorktreeCleanupMetadata: Bool {
        pendingWorktreeCleanupSourceProjectPath != nil ||
            pendingWorktreeCleanupPath != nil ||
            pendingWorktreeCleanupBranch != nil ||
            pendingCleanupSourceIdentitySystemNumber != nil ||
            pendingCleanupSourceIdentityFileNumber != nil ||
            pendingCleanupWorktreeSystemNumber != nil ||
            pendingCleanupWorktreeFileNumber != nil ||
            pendingWorktreeCleanupBranchIsOwned != nil ||
            pendingWorktreeCleanupBranchOID != nil ||
            pendingWorktreeCleanupOwnershipMarkerID != nil ||
            pendingCleanupOwnershipSourceProjectPath != nil
    }

    func setPendingWorktreeCleanup(_ provenance: ScheduledWorktreeCleanupProvenance) {
        pendingWorktreeCleanupSourceProjectPath = provenance.sourceProjectPath
        pendingWorktreeCleanupPath = provenance.worktreePath
        pendingWorktreeCleanupBranch = provenance.branch
        pendingCleanupSourceIdentitySystemNumber = String(provenance.sourceProjectIdentity.systemNumber)
        pendingCleanupSourceIdentityFileNumber = String(provenance.sourceProjectIdentity.fileNumber)
        pendingCleanupWorktreeSystemNumber = provenance.worktreeIdentity.map { String($0.systemNumber) }
        pendingCleanupWorktreeFileNumber = provenance.worktreeIdentity.map { String($0.fileNumber) }
        pendingWorktreeCleanupBranchIsOwned = provenance.branchIsOwned
        pendingWorktreeCleanupBranchOID = provenance.branchOID
        pendingWorktreeCleanupOwnershipMarkerID = provenance.ownershipMarkerID
        pendingCleanupOwnershipSourceProjectPath = provenance.ownershipSourceProjectPath
    }

    func clearPendingWorktreeOwnershipCleanup() {
        pendingCleanupWorktreeSystemNumber = nil
        pendingCleanupWorktreeFileNumber = nil
        pendingWorktreeCleanupOwnershipMarkerID = nil
        pendingCleanupOwnershipSourceProjectPath = nil
    }

    func clearPendingWorktreeCleanup() {
        pendingWorktreeCleanupSourceProjectPath = nil
        pendingWorktreeCleanupPath = nil
        pendingWorktreeCleanupBranch = nil
        pendingCleanupSourceIdentitySystemNumber = nil
        pendingCleanupSourceIdentityFileNumber = nil
        pendingWorktreeCleanupBranchIsOwned = nil
        pendingWorktreeCleanupBranchOID = nil
        clearPendingWorktreeOwnershipCleanup()
    }

    static func encodeWorkspaceIdentitySnapshot(
        _ snapshot: ScheduledTaskWorkspaceIdentitySnapshot?
    ) -> String? {
        guard let snapshot,
              let data = try? JSONEncoder().encode(snapshot) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func encodeWorkspaceCleanupProvenance(
        _ provenance: ScheduledWorktreeCleanupProvenance?
    ) -> String? {
        guard let provenance,
              let data = try? JSONEncoder().encode(provenance) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

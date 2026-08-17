import Foundation
import SwiftData

/// Reconstruction and validation of a recovered run's prepared-workspace descriptor — identity
/// checks, ownership-strategy expectations, and marker normalization — split from the
/// coordinator so interruption logic and descriptor rebuilding stay separately readable.
extension ScheduledTaskRunRecoveryCoordinator {
    func recoveredWorkspaceDescriptor(for run: ScheduledTaskRun) -> TaskWorkspaceDescriptor? {
        guard let workspaceKind = run.workspaceKindSnapshot,
              run.workspaceStrategySnapshot != nil,
              let root = canonicalAbsolutePath(run.preparedWorkspaceRoot),
              let expectedOwnershipStrategy = expectedOwnershipStrategy(for: run),
              run.preparedWorkspaceOwnershipStrategy == expectedOwnershipStrategy,
              let workspaceIdentities = run.workspaceIdentitySnapshot,
              workspaceIdentities.matchesConfiguration(
                  workspaceKind: workspaceKind,
                  projectPath: run.projectPathSnapshot,
                  grantedRootPaths: run.grantedRootsSnapshot
              )
        else {
            return nil
        }
        return makeRecoveredWorkspaceDescriptor(
            run: run,
            root: root,
            ownershipStrategy: expectedOwnershipStrategy,
            workspaceIdentities: workspaceIdentities
        )
    }

    func expectedOwnershipStrategy(for run: ScheduledTaskRun) -> TaskWorkspaceOwnershipStrategy? {
        guard let workspaceKind = ScheduledTaskWorkspaceKind(rawValue: run.workspaceKindRawValueSnapshot),
              let workspaceStrategy = ScheduledTaskWorkspaceStrategy(rawValue: run.workspaceStrategyRawValueSnapshot) else {
            return nil
        }
        switch (workspaceKind, workspaceStrategy) {
        case (.privateWorkspace, _):
            return .privateOwned
        case (.project, .localCheckout):
            return .projectLocal
        case (.project, .worktree):
            return .projectWorktreeOwned
        }
    }

    func makeRecoveredWorkspaceDescriptor(
        run: ScheduledTaskRun,
        root: String,
        ownershipStrategy: TaskWorkspaceOwnershipStrategy,
        workspaceIdentities: ScheduledTaskWorkspaceIdentitySnapshot
    ) -> TaskWorkspaceDescriptor? {
        let sourceProjectPath = ownershipStrategy == .privateOwned
            ? nil
            : canonicalAbsolutePath(run.projectPathSnapshot)
        if ownershipStrategy != .privateOwned, sourceProjectPath == nil {
            return nil
        }
        if ownershipStrategy == .projectLocal, sourceProjectPath != root {
            return nil
        }
        let markerID = recoveredMarkerID(
            run.preparedWorkspaceMarkerID,
            root: root,
            ownershipStrategy: ownershipStrategy
        )
        if ownershipStrategy != .projectLocal, markerID == nil {
            return nil
        }
        if ownershipStrategy == .projectLocal, run.preparedWorkspaceMarkerID != nil {
            return nil
        }
        let grants = run.grantedRootsSnapshot.compactMap(canonicalAbsolutePath)
        guard grants.count == run.grantedRootsSnapshot.count,
              Set(grants).count == grants.count,
              !grants.contains(root) else {
            return nil
        }
        let descriptor = TaskWorkspaceDescriptor(
            primaryRoot: root,
            grantedRoots: grants,
            ownershipStrategy: ownershipStrategy,
            ownershipMarkerID: markerID,
            sourceProjectPath: sourceProjectPath
        )
        guard descriptor.grantedRoots == run.grantedRootsSnapshot else {
            return nil
        }
        return validatedRecoveredDescriptor(
            descriptor,
            workspaceIdentities: workspaceIdentities
        )
    }

    func validatedRecoveredDescriptor(
        _ descriptor: TaskWorkspaceDescriptor,
        workspaceIdentities: ScheduledTaskWorkspaceIdentitySnapshot
    ) -> TaskWorkspaceDescriptor? {
        guard workspaceIdentitiesAreCurrent(workspaceIdentities) else {
            return nil
        }
        guard descriptor.ownershipStrategy != .projectLocal else {
            return descriptor
        }
        do {
            try workspaceOwnershipService.validateOwnedWorkspace(descriptor)
            if descriptor.ownershipStrategy == .projectWorktreeOwned {
                guard let claimedSourceIdentity = workspaceIdentities.projectRoot?.identity,
                      try workspaceOwnershipService.sourceProjectIdentity(
                          forOwnedWorktree: descriptor
                      ) == claimedSourceIdentity else {
                    return nil
                }
            }
            return descriptor
        } catch {
            return nil
        }
    }

    func workspaceIdentitiesAreCurrent(
        _ workspaceIdentities: ScheduledTaskWorkspaceIdentitySnapshot
    ) -> Bool {
        let roots = [workspaceIdentities.projectRoot].compactMap { $0 } + workspaceIdentities.grantedRoots
        return roots.allSatisfy { root in
            guard NSString(string: root.path).isAbsolutePath,
                  CanonicalPath.normalize(root.path) == root.path,
                  let currentIdentity = try? workspaceOwnershipService.directoryIdentity(at: root.path) else {
                return false
            }
            return currentIdentity == root.identity
        }
    }

    func canonicalAbsolutePath(_ path: String?) -> String? {
        guard let path,
              NSString(string: path).isAbsolutePath,
              CanonicalPath.normalize(path) == path else {
            return nil
        }
        return path
    }

    func recoveredMarkerID(
        _ markerID: String?,
        root: String,
        ownershipStrategy: TaskWorkspaceOwnershipStrategy
    ) -> String? {
        if let markerID = normalizedMarkerID(markerID) {
            return markerID
        }
        guard ownershipStrategy == .privateOwned else {
            return nil
        }
        return normalizedMarkerID(URL(fileURLWithPath: root, isDirectory: true).lastPathComponent)
    }

    func normalizedMarkerID(_ markerID: String?) -> String? {
        guard let markerID,
              let uuid = UUID(uuidString: markerID),
              uuid.uuidString.lowercased() == markerID.lowercased() else {
            return nil
        }
        return uuid.uuidString.lowercased()
    }
}

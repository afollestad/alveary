import Foundation

@testable import Alveary

final class ScheduledMaterializerOwnershipService: TaskWorkspaceOwnershipService, @unchecked Sendable {
    private let base: any TaskWorkspaceOwnershipService
    private let cancelAfterPrivateWorkspaceCreation: Bool
    private let removalError: Error?
    private let followsCanonicalDirectoryIdentity: Bool
    private let removalFailureLock = NSLock()
    private var remainingRemovalFailures: Int?

    init(
        base: any TaskWorkspaceOwnershipService,
        cancelAfterPrivateWorkspaceCreation: Bool = false,
        removalError: Error? = nil,
        followsCanonicalDirectoryIdentity: Bool = false,
        removalFailureCount: Int? = nil
    ) {
        self.base = base
        self.cancelAfterPrivateWorkspaceCreation = cancelAfterPrivateWorkspaceCreation
        self.removalError = removalError
        self.followsCanonicalDirectoryIdentity = followsCanonicalDirectoryIdentity
        remainingRemovalFailures = removalError == nil ? 0 : removalFailureCount
    }

    func createPrivateWorkspace() throws -> TaskWorkspaceDescriptor {
        let workspace = try base.createPrivateWorkspace()
        if cancelAfterPrivateWorkspaceCreation {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
        }
        return workspace
    }

    func registerOwnedWorktree(
        at path: String,
        sourceProjectPath: String,
        grantedRoots: [String]
    ) throws -> TaskWorkspaceDescriptor {
        try base.registerOwnedWorktree(
            at: path,
            sourceProjectPath: sourceProjectPath,
            grantedRoots: grantedRoots
        )
    }

    func registerOwnedWorktree(
        at path: String,
        sourceProjectPath: String,
        grantedRoots: [String],
        expectedWorktreeIdentity: TaskWorkspaceFileSystemIdentity,
        expectedSourceProjectIdentity: TaskWorkspaceFileSystemIdentity
    ) throws -> TaskWorkspaceDescriptor {
        try base.registerOwnedWorktree(
            at: path,
            sourceProjectPath: sourceProjectPath,
            grantedRoots: grantedRoots,
            expectedWorktreeIdentity: expectedWorktreeIdentity,
            expectedSourceProjectIdentity: expectedSourceProjectIdentity
        )
    }

    func registerOwnedWorktree(
        at path: String,
        sourceProjectPath: String,
        grantedRoots: [String],
        registrationProvenance: WorktreeRegistrationProvenance
    ) throws -> TaskWorkspaceDescriptor {
        try base.registerOwnedWorktree(
            at: path,
            sourceProjectPath: sourceProjectPath,
            grantedRoots: grantedRoots,
            registrationProvenance: registrationProvenance
        )
    }

    func canonicalizeGrants(_ paths: [String], excludingPrimaryRoot primaryRoot: String?) throws -> [String] {
        try base.canonicalizeGrants(paths, excludingPrimaryRoot: primaryRoot)
    }

    func directoryIdentity(at path: String) throws -> TaskWorkspaceFileSystemIdentity {
        try base.directoryIdentity(at: followsCanonicalDirectoryIdentity ? CanonicalPath.normalize(path) : path)
    }

    func sourceProjectIdentity(
        forOwnedWorktree descriptor: TaskWorkspaceDescriptor
    ) throws -> TaskWorkspaceFileSystemIdentity? {
        try base.sourceProjectIdentity(forOwnedWorktree: descriptor)
    }

    func ownedWorktreeIdentity(
        for descriptor: TaskWorkspaceDescriptor
    ) throws -> TaskWorkspaceFileSystemIdentity? {
        try base.ownedWorktreeIdentity(for: descriptor)
    }

    func validateOwnedWorkspace(_ descriptor: TaskWorkspaceDescriptor) throws {
        try base.validateOwnedWorkspace(descriptor)
    }

    func validateOwnedWorkspaceForRemoval(_ descriptor: TaskWorkspaceDescriptor) throws {
        try base.validateOwnedWorkspaceForRemoval(descriptor)
    }

    func discardOwnedWorktreeRecord(_ descriptor: TaskWorkspaceDescriptor) throws {
        try base.discardOwnedWorktreeRecord(descriptor)
    }

    func removeProvisionalOwnedWorktree(
        _ descriptor: TaskWorkspaceDescriptor,
        expectedWorktreeIdentity: TaskWorkspaceFileSystemIdentity?
    ) throws {
        try throwRemovalErrorIfNeeded()
        try base.removeProvisionalOwnedWorktree(
            descriptor,
            expectedWorktreeIdentity: expectedWorktreeIdentity
        )
    }

    func removeProvisionalWorktree(
        at path: String,
        expectedWorktreeIdentity: TaskWorkspaceFileSystemIdentity?
    ) throws {
        try throwRemovalErrorIfNeeded()
        try base.removeProvisionalWorktree(
            at: path,
            expectedWorktreeIdentity: expectedWorktreeIdentity
        )
    }

    func removeOwnedWorkspace(_ descriptor: TaskWorkspaceDescriptor) throws {
        try throwRemovalErrorIfNeeded()
        try base.removeOwnedWorkspace(descriptor)
    }

    func removeOrphanedPrivateWorkspaces(retainingMarkerIDs: Set<String>) throws {
        try base.removeOrphanedPrivateWorkspaces(retainingMarkerIDs: retainingMarkerIDs)
    }

    private func throwRemovalErrorIfNeeded() throws {
        guard let removalError else {
            return
        }
        let shouldThrow = removalFailureLock.withLock {
            guard let remainingRemovalFailures else {
                return true
            }
            guard remainingRemovalFailures > 0 else {
                return false
            }
            self.remainingRemovalFailures = remainingRemovalFailures - 1
            return true
        }
        if shouldThrow {
            throw removalError
        }
    }
}

import Foundation

struct WorktreeRegistrationProvenance: Sendable {
    let ownershipMarkerID: String?
    let expectedWorktreeIdentity: TaskWorkspaceFileSystemIdentity?
    let expectedSourceProjectIdentity: TaskWorkspaceFileSystemIdentity?
}

protocol TaskWorkspaceOwnershipService: AnyObject, Sendable {
    func createPrivateWorkspace() throws -> TaskWorkspaceDescriptor

    func registerOwnedWorktree(
        at path: String,
        sourceProjectPath: String,
        grantedRoots: [String]
    ) throws -> TaskWorkspaceDescriptor

    func registerOwnedWorktree(
        at path: String,
        sourceProjectPath: String,
        grantedRoots: [String],
        expectedWorktreeIdentity: TaskWorkspaceFileSystemIdentity,
        expectedSourceProjectIdentity: TaskWorkspaceFileSystemIdentity
    ) throws -> TaskWorkspaceDescriptor

    func registerOwnedWorktree(
        at path: String,
        sourceProjectPath: String,
        grantedRoots: [String],
        registrationProvenance: WorktreeRegistrationProvenance
    ) throws -> TaskWorkspaceDescriptor

    func canonicalizeGrants(
        _ paths: [String],
        excludingPrimaryRoot primaryRoot: String?
    ) throws -> [String]

    func directoryIdentity(at path: String) throws -> TaskWorkspaceFileSystemIdentity
    func ownedWorktreeIdentity(for descriptor: TaskWorkspaceDescriptor) throws -> TaskWorkspaceFileSystemIdentity?
    func sourceProjectIdentity(forOwnedWorktree descriptor: TaskWorkspaceDescriptor) throws -> TaskWorkspaceFileSystemIdentity?

    func validateOwnedWorkspace(_ descriptor: TaskWorkspaceDescriptor) throws
    func validateOwnedWorkspaceForRemoval(_ descriptor: TaskWorkspaceDescriptor) throws
    func discardOwnedWorktreeRecord(_ descriptor: TaskWorkspaceDescriptor) throws
    func removeProvisionalOwnedWorktree(
        _ descriptor: TaskWorkspaceDescriptor,
        expectedWorktreeIdentity: TaskWorkspaceFileSystemIdentity?
    ) throws
    func removeProvisionalWorktree(
        at path: String,
        expectedWorktreeIdentity: TaskWorkspaceFileSystemIdentity?
    ) throws
    func removeOwnedWorkspace(_ descriptor: TaskWorkspaceDescriptor) throws
    func removeOrphanedPrivateWorkspaces(retainingMarkerIDs: Set<String>) throws
}

extension TaskWorkspaceOwnershipService {
    func registerOwnedWorktree(
        at path: String,
        sourceProjectPath: String,
        grantedRoots: [String],
        registrationProvenance: WorktreeRegistrationProvenance
    ) throws -> TaskWorkspaceDescriptor {
        guard let expectedWorktreeIdentity = registrationProvenance.expectedWorktreeIdentity,
              let expectedSourceProjectIdentity = registrationProvenance.expectedSourceProjectIdentity else {
            throw TaskWorkspaceOwnershipError.workspaceNotOwned
        }
        return try registerOwnedWorktree(
            at: path,
            sourceProjectPath: sourceProjectPath,
            grantedRoots: grantedRoots,
            expectedWorktreeIdentity: expectedWorktreeIdentity,
            expectedSourceProjectIdentity: expectedSourceProjectIdentity
        )
    }

    func removeProvisionalOwnedWorktree(
        _ descriptor: TaskWorkspaceDescriptor,
        expectedWorktreeIdentity: TaskWorkspaceFileSystemIdentity?
    ) throws {
        try removeOwnedWorkspace(descriptor)
    }

    func removeProvisionalWorktree(
        at path: String,
        expectedWorktreeIdentity: TaskWorkspaceFileSystemIdentity?
    ) throws {
        guard !FileManager.default.fileExists(atPath: path) else {
            throw TaskWorkspaceOwnershipError.workspaceIdentityMismatch(path)
        }
    }
}

enum TaskWorkspaceOwnershipError: LocalizedError, Equatable, Sendable {
    case invalidAbsolutePath(String)
    case missingDirectory(String)
    case outsideOwnedRoot(String)
    case symbolicLink(String)
    case missingOwnershipMarker(String)
    case ownershipMarkerMismatch(String)
    case workspaceIdentityMismatch(String)
    case workspaceNotOwned
    case orphanCleanupFailed([String])
    case fileOperationFailed(path: String, reason: String)

    var errorDescription: String? {
        switch self {
        case let .invalidAbsolutePath(path):
            "The task workspace path is not absolute: \(path)"
        case let .missingDirectory(path):
            "The task workspace directory does not exist: \(path)"
        case let .outsideOwnedRoot(path):
            "The task workspace is outside Alveary's owned root: \(path)"
        case let .symbolicLink(path):
            "The task workspace ownership path cannot be a symbolic link: \(path)"
        case let .missingOwnershipMarker(path):
            "The task workspace ownership marker is missing: \(path)"
        case let .ownershipMarkerMismatch(path):
            "The task workspace ownership marker does not match: \(path)"
        case let .workspaceIdentityMismatch(path):
            "The task workspace at \(path) is no longer the directory Alveary created, so it was preserved."
        case .workspaceNotOwned:
            "The task workspace is not owned by Alveary."
        case .orphanCleanupFailed(let failures):
            "Some orphaned task workspaces could not be removed: \(failures.joined(separator: "; "))"
        case let .fileOperationFailed(path, reason):
            "The task workspace operation failed at \(path): \(reason)"
        }
    }
}

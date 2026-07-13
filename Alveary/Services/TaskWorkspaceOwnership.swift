import Foundation

protocol TaskWorkspaceOwnershipService: AnyObject, Sendable {
    func createPrivateWorkspace() throws -> TaskWorkspaceDescriptor

    func registerOwnedWorktree(
        at path: String,
        sourceProjectPath: String,
        grantedRoots: [String]
    ) throws -> TaskWorkspaceDescriptor

    func canonicalizeGrants(
        _ paths: [String],
        excludingPrimaryRoot primaryRoot: String?
    ) throws -> [String]

    func validateOwnedWorkspace(_ descriptor: TaskWorkspaceDescriptor) throws
    func validateOwnedWorkspaceForRemoval(_ descriptor: TaskWorkspaceDescriptor) throws
    func discardOwnedWorktreeRecord(_ descriptor: TaskWorkspaceDescriptor) throws
    func removeOwnedWorkspace(_ descriptor: TaskWorkspaceDescriptor) throws
    func removeOrphanedPrivateWorkspaces(retainingMarkerIDs: Set<String>) throws
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

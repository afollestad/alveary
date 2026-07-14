import Foundation

enum AgentThreadMode: String, Codable, Hashable, Sendable, CaseIterable {
    case project
    case task
}

enum TaskWorkspaceOwnershipStrategy: String, Codable, Hashable, Sendable, CaseIterable {
    case privateOwned
    case projectLocal
    case projectWorktreeOwned
}

struct TaskWorkspaceDescriptor: Codable, Equatable, Sendable {
    let primaryRoot: String
    let grantedRoots: [String]
    let ownershipStrategy: TaskWorkspaceOwnershipStrategy
    let ownershipMarkerID: String?
    let sourceProjectPath: String?

    init(
        primaryRoot: String,
        grantedRoots: [String] = [],
        ownershipStrategy: TaskWorkspaceOwnershipStrategy,
        ownershipMarkerID: String? = nil,
        sourceProjectPath: String? = nil
    ) {
        let normalizedPrimaryRoot = CanonicalPath.normalize(primaryRoot)
        self.primaryRoot = normalizedPrimaryRoot
        self.grantedRoots = Self.normalizedUniquePaths(
            grantedRoots,
            excluding: normalizedPrimaryRoot
        )
        self.ownershipStrategy = ownershipStrategy
        self.ownershipMarkerID = ownershipMarkerID
        self.sourceProjectPath = sourceProjectPath.map(CanonicalPath.normalize)
    }

    /// Rehydrates already-canonical persisted paths without resolving them again. Re-normalizing
    /// here would hide a later same-path symlink replacement from workspace security checks.
    init(
        persistedPrimaryRoot: String,
        persistedGrantedRoots: [String],
        ownershipStrategy: TaskWorkspaceOwnershipStrategy,
        ownershipMarkerID: String?,
        persistedSourceProjectPath: String?
    ) {
        self.primaryRoot = persistedPrimaryRoot
        self.grantedRoots = persistedGrantedRoots
        self.ownershipStrategy = ownershipStrategy
        self.ownershipMarkerID = ownershipMarkerID
        self.sourceProjectPath = persistedSourceProjectPath
    }

    private static func normalizedUniquePaths(
        _ paths: [String],
        excluding primaryRoot: String
    ) -> [String] {
        var seen = Set<String>()
        return paths.compactMap { path in
            let normalizedPath = CanonicalPath.normalize(path)
            guard normalizedPath != primaryRoot, seen.insert(normalizedPath).inserted else {
                return nil
            }
            return normalizedPath
        }
    }
}

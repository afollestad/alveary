import Foundation

struct TaskWorkspaceOwnershipRecord: Codable, Equatable {
    let version: Int
    let markerID: String
    let canonicalRoot: String
    let ownershipStrategy: TaskWorkspaceOwnershipStrategy
    let sourceProjectPath: String?
    let fileSystemIdentity: TaskWorkspaceFileSystemIdentity?
}

struct TaskWorkspaceFileSystemIdentity: Codable, Equatable {
    let systemNumber: UInt64
    let fileNumber: UInt64
}

extension DefaultTaskWorkspaceOwnershipService {
    static var defaultPrivateWorkspacesRoot: URL {
        SessionComponent.appSupportDirectory
            .appendingPathComponent("TaskWorkspaces", isDirectory: true)
            .appendingPathComponent("Private", isDirectory: true)
    }

    static var defaultWorktreeOwnershipRecordsRoot: URL {
        SessionComponent.appSupportDirectory
            .appendingPathComponent("TaskWorkspaces", isDirectory: true)
            .appendingPathComponent("WorktreeOwnership", isDirectory: true)
    }
}

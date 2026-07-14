import Foundation

extension DefaultTaskWorkspaceOwnershipService {
    func discardOwnedWorktreeRecord(_ descriptor: TaskWorkspaceDescriptor) throws {
        guard descriptor.ownershipStrategy == .projectWorktreeOwned,
              let markerID = validMarkerID(descriptor.ownershipMarkerID) else {
            throw TaskWorkspaceOwnershipError.workspaceNotOwned
        }
        let recordURL = try worktreeRecordURL(markerID: markerID)
        let record = try readRecord(at: recordURL)
        try requireMatchingWorktreeRecord(record, descriptor: descriptor)
        try removePathEntry(at: recordURL.path, description: "ownership record")
    }

    func removePrivateOwnedWorkspace(_ descriptor: TaskWorkspaceDescriptor) throws {
        let workspaceExists = pathEntryExists(atPath: descriptor.primaryRoot)
        try validateOwnedWorkspaceForRemoval(descriptor)
        guard workspaceExists else {
            return
        }
        try removePathEntry(at: descriptor.primaryRoot, description: "workspace")
    }

    func removeProjectWorktreeOwnedWorkspace(_ descriptor: TaskWorkspaceDescriptor) throws {
        if try ownedWorktreeRemovalAlreadyCompleted(descriptor) {
            return
        }
        let workspaceExists = pathEntryExists(atPath: descriptor.primaryRoot)
        try validateOwnedWorkspaceForRemoval(descriptor)
        if workspaceExists {
            try removePathEntry(at: descriptor.primaryRoot, description: "worktree")
        }
        guard let markerID = descriptor.ownershipMarkerID else {
            throw TaskWorkspaceOwnershipError.ownershipMarkerMismatch(descriptor.primaryRoot)
        }
        let recordPath = try worktreeRecordURL(markerID: markerID).path
        try removePathEntry(at: recordPath, description: "ownership record")
    }

    private func removePathEntry(at path: String, description: String) throws {
        do {
            try fileManager.removeItem(atPath: path)
        } catch {
            throw mapFileError(error, path: path)
        }
        guard !pathEntryExists(atPath: path) else {
            throw TaskWorkspaceOwnershipError.fileOperationFailed(
                path: path,
                reason: "The \(description) still exists after removal."
            )
        }
    }

    func ownedWorktreeRemovalAlreadyCompleted(_ descriptor: TaskWorkspaceDescriptor) throws -> Bool {
        guard descriptor.ownershipStrategy == .projectWorktreeOwned,
              let markerID = validMarkerID(descriptor.ownershipMarkerID),
              let sourceProjectPath = descriptor.sourceProjectPath else {
            throw TaskWorkspaceOwnershipError.workspaceNotOwned
        }
        guard NSString(string: descriptor.primaryRoot).isAbsolutePath else {
            throw TaskWorkspaceOwnershipError.invalidAbsolutePath(descriptor.primaryRoot)
        }
        guard NSString(string: sourceProjectPath).isAbsolutePath else {
            throw TaskWorkspaceOwnershipError.invalidAbsolutePath(sourceProjectPath)
        }
        guard URL(fileURLWithPath: descriptor.primaryRoot).standardizedFileURL.path == descriptor.primaryRoot,
              URL(fileURLWithPath: sourceProjectPath).standardizedFileURL.path == sourceProjectPath else {
            throw TaskWorkspaceOwnershipError.ownershipMarkerMismatch(descriptor.primaryRoot)
        }
        let recordPath = try worktreeRecordURL(markerID: markerID).path
        guard !pathEntryExists(atPath: descriptor.primaryRoot),
              !pathEntryExists(atPath: recordPath) else {
            return false
        }
        guard CanonicalPath.normalize(descriptor.primaryRoot) == descriptor.primaryRoot else {
            throw TaskWorkspaceOwnershipError.ownershipMarkerMismatch(descriptor.primaryRoot)
        }
        return true
    }

    func pathEntryExists(atPath path: String) -> Bool {
        fileManager.fileExists(atPath: path) ||
            (try? fileManager.destinationOfSymbolicLink(atPath: path)) != nil
    }

    func removeProvisionalOwnedWorktree(
        _ descriptor: TaskWorkspaceDescriptor,
        expectedWorktreeIdentity: TaskWorkspaceFileSystemIdentity?
    ) throws {
        guard descriptor.ownershipStrategy == .projectWorktreeOwned,
              let markerID = validMarkerID(descriptor.ownershipMarkerID),
              descriptor.sourceProjectPath != nil else {
            throw TaskWorkspaceOwnershipError.workspaceNotOwned
        }
        guard NSString(string: descriptor.primaryRoot).isAbsolutePath,
              URL(fileURLWithPath: descriptor.primaryRoot).standardizedFileURL.path == descriptor.primaryRoot,
              CanonicalPath.normalize(descriptor.primaryRoot) == descriptor.primaryRoot else {
            throw TaskWorkspaceOwnershipError.ownershipMarkerMismatch(descriptor.primaryRoot)
        }

        let recordPath = try worktreeRecordURL(markerID: markerID).path
        if pathEntryExists(atPath: recordPath) {
            if let expectedWorktreeIdentity,
               try ownedWorktreeIdentity(for: descriptor) != expectedWorktreeIdentity {
                throw TaskWorkspaceOwnershipError.workspaceIdentityMismatch(descriptor.primaryRoot)
            }
            try removeOwnedWorkspace(descriptor)
            return
        }
        guard pathEntryExists(atPath: descriptor.primaryRoot) else {
            return
        }
        try removeProvisionalWorktree(
            at: descriptor.primaryRoot,
            expectedWorktreeIdentity: expectedWorktreeIdentity
        )
    }

    func removeProvisionalWorktree(
        at path: String,
        expectedWorktreeIdentity: TaskWorkspaceFileSystemIdentity?
    ) throws {
        guard NSString(string: path).isAbsolutePath,
              URL(fileURLWithPath: path).standardizedFileURL.path == path,
              CanonicalPath.normalize(path) == path else {
            throw TaskWorkspaceOwnershipError.ownershipMarkerMismatch(path)
        }
        guard pathEntryExists(atPath: path) else {
            return
        }
        try rejectSymbolicLink(at: URL(fileURLWithPath: path, isDirectory: true))
        guard let expectedWorktreeIdentity,
              try directoryIdentity(at: path) == expectedWorktreeIdentity else {
            throw TaskWorkspaceOwnershipError.workspaceIdentityMismatch(path)
        }
        do {
            try fileManager.removeItem(atPath: path)
        } catch {
            throw mapFileError(error, path: path)
        }
        guard !pathEntryExists(atPath: path) else {
            throw TaskWorkspaceOwnershipError.fileOperationFailed(
                path: path,
                reason: "The provisional worktree still exists after removal."
            )
        }
    }

    func sourceProjectIdentity(
        forOwnedWorktree descriptor: TaskWorkspaceDescriptor
    ) throws -> TaskWorkspaceFileSystemIdentity? {
        try ownedWorktreeRecord(for: descriptor).sourceProjectIdentity
    }

    func ownedWorktreeIdentity(
        for descriptor: TaskWorkspaceDescriptor
    ) throws -> TaskWorkspaceFileSystemIdentity? {
        do {
            return try ownedWorktreeRecord(for: descriptor).fileSystemIdentity
        } catch let error as TaskWorkspaceOwnershipError {
            guard case .missingOwnershipMarker = error,
                  try ownedWorktreeRemovalAlreadyCompleted(descriptor) else {
                throw error
            }
            return nil
        }
    }
}

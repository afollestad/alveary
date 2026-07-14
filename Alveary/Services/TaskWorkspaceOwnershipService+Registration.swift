import Foundation

extension DefaultTaskWorkspaceOwnershipService {
    func registerOwnedWorktree(
        at path: String,
        sourceProjectPath: String,
        grantedRoots: [String] = []
    ) throws -> TaskWorkspaceDescriptor {
        try registerOwnedWorktree(
            at: path,
            sourceProjectPath: sourceProjectPath,
            grantedRoots: grantedRoots,
            registrationProvenance: WorktreeRegistrationProvenance(
                ownershipMarkerID: nil,
                expectedWorktreeIdentity: nil,
                expectedSourceProjectIdentity: nil
            )
        )
    }

    func registerOwnedWorktree(
        at path: String,
        sourceProjectPath: String,
        grantedRoots: [String],
        expectedWorktreeIdentity: TaskWorkspaceFileSystemIdentity,
        expectedSourceProjectIdentity: TaskWorkspaceFileSystemIdentity
    ) throws -> TaskWorkspaceDescriptor {
        try registerOwnedWorktree(
            at: path,
            sourceProjectPath: sourceProjectPath,
            grantedRoots: grantedRoots,
            registrationProvenance: WorktreeRegistrationProvenance(
                ownershipMarkerID: nil,
                expectedWorktreeIdentity: expectedWorktreeIdentity,
                expectedSourceProjectIdentity: expectedSourceProjectIdentity
            )
        )
    }

    func registerOwnedWorktree(
        at path: String,
        sourceProjectPath: String,
        grantedRoots: [String],
        registrationProvenance: WorktreeRegistrationProvenance
    ) throws -> TaskWorkspaceDescriptor {
        guard NSString(string: path).isAbsolutePath else {
            throw TaskWorkspaceOwnershipError.invalidAbsolutePath(path)
        }
        try rejectSymbolicLink(at: URL(fileURLWithPath: path, isDirectory: true))
        let worktreeRoot = try existingDirectoryPath(path)
        try requireExpectedDirectoryIdentity(registrationProvenance.expectedWorktreeIdentity, at: worktreeRoot)
        let canonicalGrantedRoots = try canonicalizeGrants(
            grantedRoots,
            excludingPrimaryRoot: worktreeRoot
        )
        let canonicalSourceProjectPath = try existingDirectoryPath(sourceProjectPath)
        try requireExpectedDirectoryIdentity(
            registrationProvenance.expectedSourceProjectIdentity,
            at: canonicalSourceProjectPath
        )
        let markerID: String
        if let ownershipMarkerID = registrationProvenance.ownershipMarkerID {
            guard let validatedMarkerID = validMarkerID(ownershipMarkerID) else {
                throw TaskWorkspaceOwnershipError.ownershipMarkerMismatch(path)
            }
            markerID = validatedMarkerID
        } else {
            markerID = UUID().uuidString.lowercased()
        }
        let descriptor = TaskWorkspaceDescriptor(
            primaryRoot: worktreeRoot,
            grantedRoots: canonicalGrantedRoots,
            ownershipStrategy: .projectWorktreeOwned,
            ownershipMarkerID: markerID,
            sourceProjectPath: canonicalSourceProjectPath
        )
        try persistOwnedWorktreeRegistration(
            descriptor,
            worktreeIdentity: registrationProvenance.expectedWorktreeIdentity,
            sourceProjectIdentity: registrationProvenance.expectedSourceProjectIdentity
        )
        return descriptor
    }

    private func persistOwnedWorktreeRegistration(
        _ descriptor: TaskWorkspaceDescriptor,
        worktreeIdentity: TaskWorkspaceFileSystemIdentity?,
        sourceProjectIdentity: TaskWorkspaceFileSystemIdentity?
    ) throws {
        try createControlDirectory(worktreeOwnershipRecordsRoot)
        guard let markerID = descriptor.ownershipMarkerID else {
            throw TaskWorkspaceOwnershipError.ownershipMarkerMismatch(descriptor.primaryRoot)
        }
        let recordURL = try worktreeRecordURL(markerID: markerID)
        guard !pathEntryExists(atPath: recordURL.path) else {
            throw TaskWorkspaceOwnershipError.fileOperationFailed(
                path: recordURL.path,
                reason: "An ownership record already exists."
            )
        }
        try requireExpectedDirectoryIdentity(worktreeIdentity, at: descriptor.primaryRoot)
        try requireExpectedDirectoryIdentity(sourceProjectIdentity, at: descriptor.sourceProjectPath)
        if let worktreeIdentity, let sourceProjectIdentity {
            try writeRecord(
                for: descriptor,
                to: recordURL,
                worktreeIdentity: worktreeIdentity,
                sourceProjectIdentity: sourceProjectIdentity
            )
        } else {
            try writeRecord(for: descriptor, to: recordURL)
        }
        do {
            try requireExpectedDirectoryIdentity(worktreeIdentity, at: descriptor.primaryRoot)
            try requireExpectedDirectoryIdentity(sourceProjectIdentity, at: descriptor.sourceProjectPath)
        } catch {
            try? fileManager.removeItem(at: recordURL)
            throw error
        }
    }

    private func requireExpectedDirectoryIdentity(
        _ expectedIdentity: TaskWorkspaceFileSystemIdentity?,
        at path: String?
    ) throws {
        guard let expectedIdentity, let path else {
            return
        }
        guard CanonicalPath.normalize(path) == path,
              try directoryIdentity(at: path) == expectedIdentity else {
            throw TaskWorkspaceOwnershipError.workspaceIdentityMismatch(path)
        }
    }
}

import Foundation

final class DefaultTaskWorkspaceOwnershipService: TaskWorkspaceOwnershipService, @unchecked Sendable {
    private static let privateMarkerFileName = ".alveary-task-workspace.json"

    let privateWorkspacesRoot: URL
    let worktreeOwnershipRecordsRoot: URL
    let fileManager: FileManager

    init(
        privateWorkspacesRoot: URL = DefaultTaskWorkspaceOwnershipService.defaultPrivateWorkspacesRoot,
        worktreeOwnershipRecordsRoot: URL = DefaultTaskWorkspaceOwnershipService.defaultWorktreeOwnershipRecordsRoot,
        fileManager: FileManager = .default
    ) {
        self.privateWorkspacesRoot = URL(
            fileURLWithPath: CanonicalPath.normalize(privateWorkspacesRoot.path),
            isDirectory: true
        )
        self.worktreeOwnershipRecordsRoot = URL(
            fileURLWithPath: CanonicalPath.normalize(worktreeOwnershipRecordsRoot.path),
            isDirectory: true
        )
        self.fileManager = fileManager
    }

    func createPrivateWorkspace() throws -> TaskWorkspaceDescriptor {
        try createControlDirectory(privateWorkspacesRoot)

        let markerID = UUID().uuidString.lowercased()
        let workspaceURL = privateWorkspacesRoot.appendingPathComponent(markerID, isDirectory: true)
        try requireStrictDescendant(workspaceURL.path, of: privateWorkspacesRoot.path)

        var createdWorkspace = false
        do {
            try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: false)
            createdWorkspace = true
            let descriptor = TaskWorkspaceDescriptor(
                primaryRoot: workspaceURL.path,
                ownershipStrategy: .privateOwned,
                ownershipMarkerID: markerID
            )
            try writeRecord(for: descriptor, to: privateMarkerURL(for: descriptor))
            return descriptor
        } catch {
            if createdWorkspace {
                try? fileManager.removeItem(at: workspaceURL)
            }
            throw mapFileError(error, path: workspaceURL.path)
        }
    }

    func canonicalizeGrants(
        _ paths: [String],
        excludingPrimaryRoot primaryRoot: String? = nil
    ) throws -> [String] {
        let canonicalPrimaryRoot = try primaryRoot.map(existingDirectoryPath)
        var seen = Set<String>()
        var result: [String] = []

        for path in paths {
            let canonicalPath = try existingDirectoryPath(path)
            guard canonicalPath != canonicalPrimaryRoot, seen.insert(canonicalPath).inserted else {
                continue
            }
            result.append(canonicalPath)
        }

        return result
    }

    func validateOwnedWorkspace(_ descriptor: TaskWorkspaceDescriptor) throws {
        switch descriptor.ownershipStrategy {
        case .privateOwned:
            try validatePrivateWorkspace(descriptor)
        case .projectWorktreeOwned:
            try validateOwnedWorktree(descriptor)
        case .projectLocal:
            throw TaskWorkspaceOwnershipError.workspaceNotOwned
        }
    }

    func validateOwnedWorkspaceForRemoval(_ descriptor: TaskWorkspaceDescriptor) throws {
        switch descriptor.ownershipStrategy {
        case .privateOwned:
            if pathEntryExists(atPath: descriptor.primaryRoot) {
                try validatePrivateWorkspace(descriptor)
            } else {
                try validateMissingPrivateWorkspaceForRemoval(descriptor)
            }
        case .projectWorktreeOwned:
            if try ownedWorktreeRemovalAlreadyCompleted(descriptor) {
                return
            }
            try validateOwnedWorktree(
                descriptor,
                requiresWorkspace: pathEntryExists(atPath: descriptor.primaryRoot)
            )
        case .projectLocal:
            throw TaskWorkspaceOwnershipError.workspaceNotOwned
        }
    }

    func removeOwnedWorkspace(_ descriptor: TaskWorkspaceDescriptor) throws {
        switch descriptor.ownershipStrategy {
        case .privateOwned:
            try removePrivateOwnedWorkspace(descriptor)
        case .projectWorktreeOwned:
            try removeProjectWorktreeOwnedWorkspace(descriptor)
        case .projectLocal:
            throw TaskWorkspaceOwnershipError.workspaceNotOwned
        }
    }

    func directoryIdentity(at path: String) throws -> TaskWorkspaceFileSystemIdentity {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            guard let systemNumber = attributes[.systemNumber] as? NSNumber,
                  let fileNumber = attributes[.systemFileNumber] as? NSNumber else {
                throw TaskWorkspaceOwnershipError.fileOperationFailed(
                    path: path,
                    reason: "The directory identity could not be read."
                )
            }
            return TaskWorkspaceFileSystemIdentity(
                systemNumber: systemNumber.uint64Value,
                fileNumber: fileNumber.uint64Value
            )
        } catch let error as TaskWorkspaceOwnershipError {
            throw error
        } catch {
            throw mapFileError(error, path: path)
        }
    }

    func ownedWorktreeRecord(for descriptor: TaskWorkspaceDescriptor) throws -> TaskWorkspaceOwnershipRecord {
        guard descriptor.ownershipStrategy == .projectWorktreeOwned,
              let markerID = validMarkerID(descriptor.ownershipMarkerID) else { throw TaskWorkspaceOwnershipError.workspaceNotOwned }
        let record = try readRecord(at: try worktreeRecordURL(markerID: markerID))
        try requireMatchingWorktreeRecord(record, descriptor: descriptor)
        return record
    }

    func removeOrphanedPrivateWorkspaces(retainingMarkerIDs: Set<String>) throws {
        guard fileManager.fileExists(atPath: privateWorkspacesRoot.path) else {
            return
        }
        try validateControlDirectory(privateWorkspacesRoot)
        let retainedIDs = Set(retainingMarkerIDs.compactMap(validMarkerID))
        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(
                at: privateWorkspacesRoot,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw mapFileError(error, path: privateWorkspacesRoot.path)
        }

        var failures: [String] = []
        for child in children.sorted(by: { $0.path < $1.path }) {
            guard let markerID = validMarkerID(child.lastPathComponent) else {
                continue
            }
            guard !retainedIDs.contains(markerID) else {
                continue
            }
            let descriptor = TaskWorkspaceDescriptor(
                primaryRoot: child.path,
                ownershipStrategy: .privateOwned,
                ownershipMarkerID: markerID
            )
            do {
                try removeOwnedWorkspace(descriptor)
            } catch {
                failures.append("\(child.path): \(error.localizedDescription)")
            }
        }
        guard failures.isEmpty else {
            throw TaskWorkspaceOwnershipError.orphanCleanupFailed(failures)
        }
    }
}

extension DefaultTaskWorkspaceOwnershipService {
    func validatePrivateWorkspace(_ descriptor: TaskWorkspaceDescriptor) throws {
        try validateControlDirectory(privateWorkspacesRoot)
        guard let markerID = validMarkerID(descriptor.ownershipMarkerID) else {
            throw TaskWorkspaceOwnershipError.ownershipMarkerMismatch(descriptor.primaryRoot)
        }
        let canonicalRoot = try existingDirectoryPath(descriptor.primaryRoot)
        guard canonicalRoot == descriptor.primaryRoot else {
            throw TaskWorkspaceOwnershipError.ownershipMarkerMismatch(descriptor.primaryRoot)
        }
        try requireStrictDescendant(canonicalRoot, of: privateWorkspacesRoot.path)
        try rejectSymbolicLinks(from: privateWorkspacesRoot, through: URL(fileURLWithPath: canonicalRoot, isDirectory: true))

        let markerURL = privateMarkerURL(for: descriptor)
        let record = try readRecord(at: markerURL)
        try requireMatchingRecord(
            record,
            expected: TaskWorkspaceOwnershipRecord(
                version: 1,
                markerID: markerID,
                canonicalRoot: canonicalRoot,
                ownershipStrategy: .privateOwned,
                sourceProjectPath: nil,
                fileSystemIdentity: nil,
                sourceProjectIdentity: nil
            ),
            markerPath: markerURL.path
        )
    }

    func validateMissingPrivateWorkspaceForRemoval(_ descriptor: TaskWorkspaceDescriptor) throws {
        guard let markerID = validMarkerID(descriptor.ownershipMarkerID),
              URL(fileURLWithPath: descriptor.primaryRoot).lastPathComponent == markerID else {
            throw TaskWorkspaceOwnershipError.ownershipMarkerMismatch(descriptor.primaryRoot)
        }
        let normalizedRoot = CanonicalPath.normalize(descriptor.primaryRoot)
        guard normalizedRoot == descriptor.primaryRoot else {
            throw TaskWorkspaceOwnershipError.ownershipMarkerMismatch(descriptor.primaryRoot)
        }
        try requireStrictDescendant(normalizedRoot, of: privateWorkspacesRoot.path)
    }

    func validateOwnedWorktree(
        _ descriptor: TaskWorkspaceDescriptor,
        requiresWorkspace: Bool = true
    ) throws {
        try validateControlDirectory(worktreeOwnershipRecordsRoot)
        guard let markerID = validMarkerID(descriptor.ownershipMarkerID) else {
            throw TaskWorkspaceOwnershipError.ownershipMarkerMismatch(descriptor.primaryRoot)
        }
        guard NSString(string: descriptor.primaryRoot).isAbsolutePath else {
            throw TaskWorkspaceOwnershipError.invalidAbsolutePath(descriptor.primaryRoot)
        }
        let canonicalRoot: String
        if requiresWorkspace {
            canonicalRoot = try existingDirectoryPath(descriptor.primaryRoot)
        } else {
            canonicalRoot = CanonicalPath.normalize(descriptor.primaryRoot)
        }
        guard canonicalRoot == descriptor.primaryRoot else {
            throw TaskWorkspaceOwnershipError.ownershipMarkerMismatch(descriptor.primaryRoot)
        }
        if requiresWorkspace {
            try rejectSymbolicLink(at: URL(fileURLWithPath: canonicalRoot, isDirectory: true))
        }

        let markerURL = try worktreeRecordURL(markerID: markerID)
        let record = try readRecord(at: markerURL)
        try requireMatchingWorktreeRecord(record, descriptor: descriptor)
        guard let recordedIdentity = record.fileSystemIdentity else {
            throw TaskWorkspaceOwnershipError.ownershipMarkerMismatch(markerURL.path)
        }
        if requiresWorkspace,
           try directoryIdentity(at: canonicalRoot) != recordedIdentity {
            throw TaskWorkspaceOwnershipError.workspaceIdentityMismatch(canonicalRoot)
        }
    }

    func requireMatchingWorktreeRecord(
        _ record: TaskWorkspaceOwnershipRecord,
        descriptor: TaskWorkspaceDescriptor
    ) throws {
        guard let markerID = validMarkerID(descriptor.ownershipMarkerID),
              record.version == 1,
              record.markerID == markerID,
              record.canonicalRoot == descriptor.primaryRoot,
              record.ownershipStrategy == .projectWorktreeOwned,
              record.sourceProjectPath == descriptor.sourceProjectPath else {
            throw TaskWorkspaceOwnershipError.ownershipMarkerMismatch(descriptor.primaryRoot)
        }
    }

    func requireMatchingRecord(
        _ record: TaskWorkspaceOwnershipRecord,
        expected: TaskWorkspaceOwnershipRecord,
        markerPath: String
    ) throws {
        guard record == expected else {
            throw TaskWorkspaceOwnershipError.ownershipMarkerMismatch(markerPath)
        }
    }

    func existingDirectoryPath(_ path: String) throws -> String {
        guard NSString(string: path).isAbsolutePath else {
            throw TaskWorkspaceOwnershipError.invalidAbsolutePath(path)
        }

        let canonicalPath = CanonicalPath.normalize(path)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: canonicalPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw TaskWorkspaceOwnershipError.missingDirectory(canonicalPath)
        }
        return canonicalPath
    }

    func createDirectory(_ url: URL) throws {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw mapFileError(error, path: url.path)
        }
    }

    func createControlDirectory(_ url: URL) throws {
        if pathEntryExists(atPath: url.path) {
            try rejectSymbolicLink(at: url)
        }
        try createDirectory(url)
        try validateControlDirectory(url)
    }

    func validateControlDirectory(_ url: URL) throws {
        let canonicalPath = try existingDirectoryPath(url.path)
        guard canonicalPath == url.path else {
            throw TaskWorkspaceOwnershipError.symbolicLink(url.path)
        }
        try rejectSymbolicLink(at: url)
    }

    func requireStrictDescendant(_ path: String, of rootPath: String) throws {
        let pathComponents = URL(fileURLWithPath: CanonicalPath.normalize(path)).pathComponents
        let rootComponents = URL(fileURLWithPath: CanonicalPath.normalize(rootPath)).pathComponents
        guard pathComponents.count > rootComponents.count,
              Array(pathComponents.prefix(rootComponents.count)) == rootComponents
        else {
            throw TaskWorkspaceOwnershipError.outsideOwnedRoot(path)
        }
    }

    func rejectSymbolicLinks(from rootURL: URL, through targetURL: URL) throws {
        try rejectSymbolicLink(at: rootURL)
        let rootComponents = rootURL.pathComponents
        let targetComponents = targetURL.pathComponents
        guard targetComponents.count >= rootComponents.count,
              Array(targetComponents.prefix(rootComponents.count)) == rootComponents
        else {
            throw TaskWorkspaceOwnershipError.outsideOwnedRoot(targetURL.path)
        }

        var currentURL = rootURL
        for component in targetComponents.dropFirst(rootComponents.count) {
            currentURL.appendPathComponent(component)
            try rejectSymbolicLink(at: currentURL)
        }
    }

    func rejectSymbolicLink(at url: URL) throws {
        do {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                throw TaskWorkspaceOwnershipError.symbolicLink(url.path)
            }
        } catch let error as TaskWorkspaceOwnershipError {
            throw error
        } catch {
            throw mapFileError(error, path: url.path)
        }
    }

    func privateMarkerURL(for descriptor: TaskWorkspaceDescriptor) -> URL {
        URL(fileURLWithPath: descriptor.primaryRoot, isDirectory: true)
            .appendingPathComponent(Self.privateMarkerFileName, isDirectory: false)
    }

    func worktreeRecordURL(markerID: String) throws -> URL {
        guard let markerID = validMarkerID(markerID) else {
            throw TaskWorkspaceOwnershipError.ownershipMarkerMismatch(worktreeOwnershipRecordsRoot.path)
        }
        return worktreeOwnershipRecordsRoot.appendingPathComponent("\(markerID).json", isDirectory: false)
    }

    func validMarkerID(_ markerID: String?) -> String? {
        guard let markerID,
              let uuid = UUID(uuidString: markerID),
              uuid.uuidString.lowercased() == markerID.lowercased()
        else {
            return nil
        }
        return uuid.uuidString.lowercased()
    }

    func writeRecord(for descriptor: TaskWorkspaceDescriptor, to url: URL) throws {
        try writeRecord(
            for: descriptor,
            to: url,
            worktreeIdentity: descriptor.ownershipStrategy == .projectWorktreeOwned
                ? directoryIdentity(at: descriptor.primaryRoot)
                : nil,
            sourceProjectIdentity: try descriptor.sourceProjectPath.map(directoryIdentity(at:))
        )
    }

    func writeRecord(
        for descriptor: TaskWorkspaceDescriptor,
        to url: URL,
        worktreeIdentity: TaskWorkspaceFileSystemIdentity?,
        sourceProjectIdentity: TaskWorkspaceFileSystemIdentity?
    ) throws {
        guard let markerID = validMarkerID(descriptor.ownershipMarkerID) else {
            throw TaskWorkspaceOwnershipError.ownershipMarkerMismatch(url.path)
        }
        let record = TaskWorkspaceOwnershipRecord(
            version: 1,
            markerID: markerID,
            canonicalRoot: descriptor.primaryRoot,
            ownershipStrategy: descriptor.ownershipStrategy,
            sourceProjectPath: descriptor.sourceProjectPath,
            fileSystemIdentity: worktreeIdentity,
            sourceProjectIdentity: sourceProjectIdentity
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(record).write(to: url, options: [.atomic])
        } catch {
            throw mapFileError(error, path: url.path)
        }
    }

    func readRecord(at url: URL) throws -> TaskWorkspaceOwnershipRecord {
        guard pathEntryExists(atPath: url.path) else {
            throw TaskWorkspaceOwnershipError.missingOwnershipMarker(url.path)
        }
        try rejectSymbolicLink(at: url)

        do {
            return try JSONDecoder().decode(TaskWorkspaceOwnershipRecord.self, from: Data(contentsOf: url))
        } catch {
            throw TaskWorkspaceOwnershipError.ownershipMarkerMismatch(url.path)
        }
    }

    func mapFileError(_ error: Error, path: String) -> TaskWorkspaceOwnershipError {
        if let ownershipError = error as? TaskWorkspaceOwnershipError {
            return ownershipError
        }
        return .fileOperationFailed(path: path, reason: error.localizedDescription)
    }
}

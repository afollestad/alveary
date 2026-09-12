import CryptoKit
import Foundation

enum ReviewTeamHistoryStoreError: Error, Equatable, LocalizedError {
    case deletedConversation
    case invalidArtifact
    case missingArtifact
    case changedArtifact
    case pathEscapedRoot
    case fileTooLarge(limitBytes: Int)
    case runTooLarge(limitBytes: Int)

    var errorDescription: String? {
        switch self {
        case .deletedConversation:
            "The task was deleted; its review history can no longer be saved."
        case .invalidArtifact:
            "The review history artifact is invalid."
        case .missingArtifact:
            "The review history artifact is missing."
        case .changedArtifact:
            "The review history artifact changed after it was saved."
        case .pathEscapedRoot:
            "The review history path escaped its private storage directory."
        case .fileTooLarge(let limitBytes):
            "The review history file exceeds its \(limitBytes)-byte limit."
        case .runTooLarge(let limitBytes):
            "The review run exceeds its \(limitBytes)-byte history limit."
        }
    }
}

/// Durable, content-addressed history, separate from worker packets that are deleted after execution.
actor ReviewTeamHistoryStore {
    init(
        rootDirectory: URL,
        maximumRunBytes: Int = 128 * 1024 * 1024,
        maximumFileBytes: Int = 64 * 1024 * 1024
    ) {
        self.rootDirectory = rootDirectory.standardizedFileURL
        canonicalRootIdentity = Self.canonicalURL(rootDirectory)
        self.maximumRunBytes = max(0, maximumRunBytes)
        self.maximumFileBytes = max(0, maximumFileBytes)
    }

    /// Only caller-supplied bytes are captured; names are display labels, never filesystem paths.
    func save(conversationID: String, runID: String, name: String, data: Data) throws -> ReviewHistoryArtifact {
        guard !deletedConversationIDs.contains(conversationID) else {
            throw ReviewTeamHistoryStoreError.deletedConversation
        }
        guard data.count <= maximumFileBytes else {
            throw ReviewTeamHistoryStoreError.fileTooLarge(limitBytes: maximumFileBytes)
        }
        let run = try runDirectory(conversationID: conversationID, runID: runID, create: true)
        let artifact = ReviewHistoryArtifact(id: Self.digest(data), name: name, byteCount: data.count)
        let destination = run.appendingPathComponent(artifact.id)
        let usedBytes = try runByteCount(run)
        if try attributes(at: destination) == nil {
            guard data.count <= maximumRunBytes - usedBytes else {
                throw ReviewTeamHistoryStoreError.runTooLarge(limitBytes: maximumRunBytes)
            }
            try data.write(to: destination, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o400], ofItemAtPath: destination.path)
        }
        _ = try readBlob(artifact, at: destination)
        savedConversationHashes.insert(Self.digest(Data(conversationID.utf8)))
        return artifact
    }

    func read(_ artifact: ReviewHistoryArtifact, conversationID: String, runID: String) throws -> Data {
        guard Self.isDigest(artifact.id), artifact.byteCount >= 0, artifact.byteCount <= maximumFileBytes else {
            throw ReviewTeamHistoryStoreError.invalidArtifact
        }
        let run = try runDirectory(conversationID: conversationID, runID: runID, create: false)
        return try readBlob(artifact, at: run.appendingPathComponent(artifact.id))
    }

    /// Tombstone before IO so a late worker callback cannot recreate a deleted task's history.
    func remove(conversationID: String) throws {
        deletedConversationIDs.insert(conversationID)
        savedConversationHashes.remove(Self.digest(Data(conversationID.utf8)))
        guard let root = try validatedRoot(create: false) else { return }
        let directory = root.appendingPathComponent(Self.digest(Data(conversationID.utf8)), isDirectory: true)
        guard try attributes(at: directory) != nil else { return }
        try validateConversation(directory)
        try fileManager.removeItem(at: directory)
    }

    /// Protect writes racing a startup snapshot that predates their task's creation.
    func prune(retainingConversationIDs: Set<String>) throws {
        guard let root = try validatedRoot(create: false) else { return }
        let retained = Set(retainingConversationIDs.map { Self.digest(Data($0.utf8)) }).union(savedConversationHashes)
        let directories = try children(of: root)
        for directory in directories {
            guard Self.isDigest(directory.lastPathComponent) else {
                throw ReviewTeamHistoryStoreError.pathEscapedRoot
            }
            try validateConversation(directory)
        }
        for directory in directories where !retained.contains(directory.lastPathComponent) {
            try fileManager.removeItem(at: directory)
        }
    }

    private let rootDirectory: URL
    private let canonicalRootIdentity: URL
    private let maximumRunBytes: Int
    private let maximumFileBytes: Int
    private let fileManager = FileManager.default
    private var deletedConversationIDs: Set<String> = []
    private var savedConversationHashes: Set<String> = []
}

private extension ReviewTeamHistoryStore {
    func runDirectory(conversationID: String, runID: String, create: Bool) throws -> URL {
        guard let root = try validatedRoot(create: create) else {
            throw ReviewTeamHistoryStoreError.missingArtifact
        }
        let conversation = root.appendingPathComponent(Self.digest(Data(conversationID.utf8)), isDirectory: true)
        try ensureDirectory(conversation, create: create)
        let run = conversation.appendingPathComponent(Self.digest(Data(runID.utf8)), isDirectory: true)
        try ensureDirectory(run, create: create)
        return run
    }

    func validatedRoot(create: Bool) throws -> URL? {
        guard rootDirectory.isFileURL,
              Self.canonicalURL(rootDirectory).path == canonicalRootIdentity.path else {
            throw ReviewTeamHistoryStoreError.pathEscapedRoot
        }
        if let attributes = try attributes(at: rootDirectory) {
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw ReviewTeamHistoryStoreError.pathEscapedRoot
            }
        } else if create {
            try fileManager.createDirectory(
                at: rootDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } else {
            return nil
        }
        try validateDirectory(canonicalRootIdentity)
        return canonicalRootIdentity
    }

    func ensureDirectory(_ directory: URL, create: Bool) throws {
        try validatePath(directory)
        if try attributes(at: directory) == nil {
            guard create else { throw ReviewTeamHistoryStoreError.missingArtifact }
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try validateDirectory(directory)
    }

    func validatePath(_ url: URL) throws {
        guard url.standardizedFileURL.path.hasPrefix(canonicalRootIdentity.path + "/"),
              Self.canonicalURL(url).path == url.standardizedFileURL.path else {
            throw ReviewTeamHistoryStoreError.pathEscapedRoot
        }
    }

    func validateDirectory(_ directory: URL) throws {
        if directory.path != canonicalRootIdentity.path { try validatePath(directory) }
        guard let attributes = try attributes(at: directory),
              attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700 else {
            throw ReviewTeamHistoryStoreError.pathEscapedRoot
        }
    }

    func validateConversation(_ directory: URL) throws {
        try validateDirectory(directory)
        for run in try children(of: directory) {
            guard Self.isDigest(run.lastPathComponent) else { throw ReviewTeamHistoryStoreError.pathEscapedRoot }
            try validateDirectory(run)
            for blob in try children(of: run) {
                _ = try regularFileAttributes(at: blob)
            }
        }
    }

    func runByteCount(_ directory: URL) throws -> Int {
        var total = 0
        for blob in try children(of: directory) {
            let attributes = try blobAttributes(at: blob)
            guard let size = (attributes[.size] as? NSNumber)?.intValue, size >= 0, size <= maximumFileBytes else {
                throw ReviewTeamHistoryStoreError.changedArtifact
            }
            guard size <= maximumRunBytes - total else {
                throw ReviewTeamHistoryStoreError.runTooLarge(limitBytes: maximumRunBytes)
            }
            total += size
        }
        return total
    }

    func blobAttributes(at url: URL) throws -> [FileAttributeKey: Any] {
        guard Self.isDigest(url.lastPathComponent) else { throw ReviewTeamHistoryStoreError.invalidArtifact }
        let attributes = try regularFileAttributes(at: url)
        guard (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o400 else {
            throw ReviewTeamHistoryStoreError.changedArtifact
        }
        return attributes
    }

    func regularFileAttributes(at url: URL) throws -> [FileAttributeKey: Any] {
        try validatePath(url)
        guard let attributes = try attributes(at: url) else { throw ReviewTeamHistoryStoreError.missingArtifact }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.referenceCount] as? NSNumber)?.intValue == 1 else {
            throw ReviewTeamHistoryStoreError.pathEscapedRoot
        }
        return attributes
    }

    func readBlob(_ artifact: ReviewHistoryArtifact, at url: URL) throws -> Data {
        let attributes = try blobAttributes(at: url)
        guard (attributes[.size] as? NSNumber)?.intValue == artifact.byteCount else {
            throw ReviewTeamHistoryStoreError.changedArtifact
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            guard chunk.count <= artifact.byteCount - data.count else {
                throw ReviewTeamHistoryStoreError.changedArtifact
            }
            data.append(chunk)
        }
        guard data.count == artifact.byteCount, Self.digest(data) == artifact.id else {
            throw ReviewTeamHistoryStoreError.changedArtifact
        }
        return data
    }

    func children(of directory: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
    }

    func attributes(at url: URL) throws -> [FileAttributeKey: Any]? {
        do {
            return try fileManager.attributesOfItem(atPath: url.path)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && (
            error.code == CocoaError.fileReadNoSuchFile.rawValue || error.code == CocoaError.fileNoSuchFile.rawValue
        ) {
            return nil
        }
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// Foundation drops directory hints on missing paths and may leave their existing ancestors unresolved.
    static func canonicalURL(_ url: URL) -> URL {
        guard url.isFileURL else { return url }
        var ancestor = url.standardizedFileURL
        var missingComponents: [String] = []
        while ancestor.path != "/", !FileManager.default.fileExists(atPath: ancestor.path) {
            missingComponents.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        var canonical = ancestor.resolvingSymlinksInPath().standardizedFileURL
        for component in missingComponents.reversed() {
            canonical.appendPathComponent(component)
        }
        return canonical
    }
}

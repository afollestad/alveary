import CryptoKit
import Foundation

/// A process-lifetime capability for an immutable packet authored by Alveary.
struct ReviewPacketLease: Equatable, Sendable {
    let id: String
    let runID: String
    let rootDirectoryURL: URL
    let directoryURL: URL
    let fileNames: [String]
    let inputHash: String

    fileprivate init(
        id: String,
        runID: String,
        rootDirectoryURL: URL,
        directoryURL: URL,
        fileNames: [String],
        inputHash: String
    ) {
        self.id = id
        self.runID = runID
        self.rootDirectoryURL = rootDirectoryURL
        self.directoryURL = directoryURL
        self.fileNames = fileNames
        self.inputHash = inputHash
    }

    func fileURL(named fileName: String) -> URL? {
        guard fileNames.contains(fileName) else {
            return nil
        }
        return directoryURL.appendingPathComponent(fileName, isDirectory: false)
    }

    func validate(fileManager: FileManager = .default) throws {
        let root = rootDirectoryURL.resolvingSymlinksInPath().standardizedFileURL
        let directory = directoryURL.resolvingSymlinksInPath().standardizedFileURL
        let runDirectory = directory.deletingLastPathComponent()
        guard root == rootDirectoryURL.standardizedFileURL,
              directory == directoryURL.standardizedFileURL,
              ReviewPacketStore.contains(runDirectory, in: root),
              ReviewPacketStore.contains(directory, in: runDirectory),
              runDirectory.lastPathComponent == ReviewPacketStore.digest(runID),
              directory.lastPathComponent == id else {
            throw ReviewPacketStoreError.pathEscapedRoot
        }
        try Self.validateDirectory(root, permissions: 0o700, fileManager: fileManager)
        try Self.validateDirectory(runDirectory, permissions: 0o700, fileManager: fileManager)
        try Self.validateDirectory(directory, permissions: 0o500, fileManager: fileManager)
        let actualFileNames = try fileManager.contentsOfDirectory(atPath: directory.path).sorted()
        guard actualFileNames == fileNames,
              try ReviewPacketStore.inputHash(
                  directory: directory,
                  fileNames: fileNames,
                  fileManager: fileManager
              ) == inputHash else {
            throw ReviewPacketStoreError.invalidLease
        }
    }

    private static func validateDirectory(_ directory: URL, permissions: Int, fileManager: FileManager) throws {
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let attributes = try fileManager.attributesOfItem(atPath: directory.path)
        guard values.isDirectory == true,
              values.isSymbolicLink != true,
              (attributes[.posixPermissions] as? NSNumber)?.intValue == permissions else {
            throw ReviewPacketStoreError.invalidLease
        }
    }
}

enum ReviewPacketStoreError: Error, Equatable, LocalizedError {
    case emptyRunID
    case invalidFileName(String)
    case pathEscapedRoot
    case invalidLease
    case fileWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyRunID:
            "A review packet requires a run id."
        case .invalidFileName(let fileName):
            "Invalid review packet file name: \(fileName)"
        case .pathEscapedRoot:
            "The review packet path escaped its private root."
        case .invalidLease:
            "The review packet changed after it was created."
        case .fileWriteFailed(let message):
            "Could not write the review packet. \(message)"
        }
    }
}

/// Creates private immutable input directories without treating arbitrary paths as trusted projects.
actor ReviewPacketStore {
    private let fileManager: FileManager
    private let rootDirectory: URL
    private var canonicalRootIdentity: URL?

    init(
        rootDirectory: URL = ReviewPacketStore.defaultRootDirectory(),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.fileManager = fileManager
    }

    func create(runID: String, files: [String: Data]) throws -> ReviewPacketLease {
        guard !runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReviewPacketStoreError.emptyRunID
        }
        let fileNames = files.keys.sorted()
        try fileNames.forEach(Self.validateFileName)

        do {
            let (leaseID, leaseDirectory) = try makeLeaseDirectory(runID: runID)
            try write(files: files, fileNames: fileNames, to: leaseDirectory)
            return ReviewPacketLease(
                id: leaseID,
                runID: runID,
                rootDirectoryURL: rootDirectory.resolvingSymlinksInPath().standardizedFileURL,
                directoryURL: leaseDirectory,
                fileNames: fileNames,
                inputHash: Self.inputHash(files: files, fileNames: fileNames)
            )
        } catch let error as ReviewPacketStoreError {
            throw error
        } catch {
            throw ReviewPacketStoreError.fileWriteFailed(error.localizedDescription)
        }
    }

    func remove(_ lease: ReviewPacketLease) throws {
        guard fileManager.fileExists(atPath: rootDirectory.path) else {
            return
        }
        let canonicalRoot = try validatedRootDirectory()
        guard let expectedRunDirectory = try validatedRunDirectory(
            runID: lease.runID,
            canonicalRoot: canonicalRoot
        ) else {
            return
        }
        let expectedLeaseDirectory = expectedRunDirectory
            .appendingPathComponent(lease.id, isDirectory: true)
            .standardizedFileURL
        guard lease.rootDirectoryURL.standardizedFileURL == canonicalRoot,
              lease.directoryURL.standardizedFileURL == expectedLeaseDirectory else {
            throw ReviewPacketStoreError.pathEscapedRoot
        }
        guard fileManager.fileExists(atPath: expectedLeaseDirectory.path) else {
            return
        }
        let leaseDirectory = lease.directoryURL.resolvingSymlinksInPath().standardizedFileURL
        let values = try lease.directoryURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard leaseDirectory == expectedLeaseDirectory,
              values.isDirectory == true,
              values.isSymbolicLink != true else {
            throw ReviewPacketStoreError.pathEscapedRoot
        }
        try Self.makeDirectoryWritable(leaseDirectory, fileManager: fileManager)
        try fileManager.removeItem(at: leaseDirectory)
        try removeRunDirectoryIfEmpty(expectedRunDirectory)
    }

    func remove(runID: String) throws {
        guard !runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReviewPacketStoreError.emptyRunID
        }
        guard fileManager.fileExists(atPath: rootDirectory.path) else {
            return
        }
        let canonicalRoot = try validatedRootDirectory()
        guard let runDirectory = try validatedRunDirectory(
            runID: runID,
            canonicalRoot: canonicalRoot
        ) else {
            return
        }
        for child in try fileManager.contentsOfDirectory(
            at: runDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            let canonicalChild = child.resolvingSymlinksInPath().standardizedFileURL
            guard Self.contains(canonicalChild, in: runDirectory) else {
                throw ReviewPacketStoreError.pathEscapedRoot
            }
            if try canonicalChild.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                try Self.makeDirectoryWritable(canonicalChild, fileManager: fileManager)
            }
        }
        try fileManager.removeItem(at: runDirectory)
    }

    private func makeLeaseDirectory(runID: String) throws -> (String, URL) {
        try Self.ensurePrivateDirectory(rootDirectory, withIntermediateDirectories: true, fileManager: fileManager)
        let canonicalRoot = try validatedRootDirectory()
        let requestedRunDirectory = canonicalRoot.appendingPathComponent(Self.digest(runID), isDirectory: true)
        try Self.ensurePrivateDirectory(
            requestedRunDirectory,
            withIntermediateDirectories: false,
            fileManager: fileManager
        )
        let runDirectory = requestedRunDirectory.resolvingSymlinksInPath().standardizedFileURL
        guard Self.contains(runDirectory, in: canonicalRoot) else {
            throw ReviewPacketStoreError.pathEscapedRoot
        }
        let leaseID = UUID().uuidString
        let leaseDirectory = runDirectory.appendingPathComponent(leaseID, isDirectory: true)
        guard Self.contains(leaseDirectory, in: canonicalRoot) else {
            throw ReviewPacketStoreError.pathEscapedRoot
        }
        try fileManager.createDirectory(
            at: leaseDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return (leaseID, leaseDirectory)
    }

    private func validatedRootDirectory() throws -> URL {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ReviewPacketStoreError.pathEscapedRoot
        }
        let values = try rootDirectory.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw ReviewPacketStoreError.pathEscapedRoot
        }
        let canonicalRoot = rootDirectory.resolvingSymlinksInPath().standardizedFileURL
        if let canonicalRootIdentity, canonicalRootIdentity != canonicalRoot {
            throw ReviewPacketStoreError.pathEscapedRoot
        }
        canonicalRootIdentity = canonicalRoot
        return canonicalRoot
    }

    private func validatedRunDirectory(runID: String, canonicalRoot: URL) throws -> URL? {
        let requestedRunDirectory = rootDirectory.appendingPathComponent(Self.digest(runID), isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: requestedRunDirectory.path, isDirectory: &isDirectory) else {
            return nil
        }
        let values = try requestedRunDirectory.resourceValues(forKeys: [.isSymbolicLinkKey])
        let runDirectory = requestedRunDirectory.resolvingSymlinksInPath().standardizedFileURL
        let expectedRunDirectory = canonicalRoot
            .appendingPathComponent(Self.digest(runID), isDirectory: true)
            .standardizedFileURL
        guard isDirectory.boolValue,
              values.isSymbolicLink != true,
              runDirectory == expectedRunDirectory else {
            throw ReviewPacketStoreError.pathEscapedRoot
        }
        return runDirectory
    }

    private func write(files: [String: Data], fileNames: [String], to leaseDirectory: URL) throws {
        do {
            for fileName in fileNames {
                guard let data = files[fileName] else {
                    continue
                }
                let fileURL = leaseDirectory.appendingPathComponent(fileName, isDirectory: false)
                try data.write(to: fileURL, options: .atomic)
                try fileManager.setAttributes([.posixPermissions: 0o400], ofItemAtPath: fileURL.path)
            }
            try fileManager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: leaseDirectory.path)
        } catch {
            try? Self.makeDirectoryWritable(leaseDirectory, fileManager: fileManager)
            try? fileManager.removeItem(at: leaseDirectory)
            throw error
        }
    }

    private func removeRunDirectoryIfEmpty(_ directory: URL) throws {
        guard fileManager.fileExists(atPath: directory.path),
              try fileManager.contentsOfDirectory(atPath: directory.path).isEmpty else {
            return
        }
        try fileManager.removeItem(at: directory)
    }

    private static func validateFileName(_ fileName: String) throws {
        guard !fileName.isEmpty,
              fileName != ".",
              fileName != "..",
              !fileName.contains("/"),
              !fileName.contains("\\"),
              !fileName.contains("\0") else {
            throw ReviewPacketStoreError.invalidFileName(fileName)
        }
    }

    fileprivate static func inputHash(files: [String: Data], fileNames: [String]) -> String {
        var hasher = SHA256()
        for fileName in fileNames {
            guard let data = files[fileName] else {
                continue
            }
            hasher.update(data: Data("\(fileName.utf8.count):\(fileName):\(data.count):".utf8))
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    fileprivate static func inputHash(
        directory: URL,
        fileNames: [String],
        fileManager: FileManager
    ) throws -> String {
        var hasher = SHA256()
        for fileName in fileNames {
            try Task.checkCancellation()
            let fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
            let canonicalFile = fileURL.resolvingSymlinksInPath().standardizedFileURL
            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            guard canonicalFile == fileURL.standardizedFileURL,
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let byteCount = values.fileSize,
                  (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o400 else {
                throw ReviewPacketStoreError.invalidLease
            }
            hasher.update(data: Data("\(fileName.utf8.count):\(fileName):\(byteCount):".utf8))
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            while let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty {
                try Task.checkCancellation()
                hasher.update(data: data)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    fileprivate static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    fileprivate static func contains(_ candidate: URL, in root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        return candidatePath.hasPrefix(rootPath + "/")
    }

    private static func makeDirectoryWritable(_ directory: URL, fileManager: FileManager) throws {
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private static func ensurePrivateDirectory(
        _ directory: URL,
        withIntermediateDirectories: Bool,
        fileManager: FileManager
    ) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard isDirectory.boolValue, values.isSymbolicLink != true else {
                throw ReviewPacketStoreError.pathEscapedRoot
            }
        } else {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: withIntermediateDirectories,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private static func defaultRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Alveary", isDirectory: true)
            .appendingPathComponent("ReviewPackets", isDirectory: true)
    }
}

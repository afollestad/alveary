import CryptoKit
import Foundation

/// A write-ahead cancellation receipt survives a failed SwiftData save; recovery checks it before launching workers.
@MainActor
final class ReviewTeamCancellationStore {
    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory.standardizedFileURL
    }

    func record(runID: String) throws {
        guard let root = try validatedRoot(create: true) else { return }
        let marker = markerURL(runID: runID, root: root)
        if try attributes(at: marker) == nil {
            try Data().write(to: marker, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
        }
        try validateMarker(marker)
        let handle = try FileHandle(forWritingTo: marker)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    func contains(runID: String) throws -> Bool {
        guard let root = try validatedRoot(create: false) else { return false }
        let marker = markerURL(runID: runID, root: root)
        guard try attributes(at: marker) != nil else { return false }
        try validateMarker(marker)
        return true
    }

    /// Remove only after the cancelled run is durably saved; a leftover receipt is harmless.
    func remove(runID: String) throws {
        guard try contains(runID: runID), let root = try validatedRoot(create: false) else { return }
        try FileManager.default.removeItem(at: markerURL(runID: runID, root: root))
    }

    private let rootDirectory: URL
    private var canonicalRoot: URL?

    private func validatedRoot(create: Bool) throws -> URL? {
        guard rootDirectory.isFileURL else { throw ReviewTeamError.invalidOutput("Invalid cancellation storage directory.") }
        if try attributes(at: rootDirectory) == nil {
            guard create else { return nil }
            try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        let root = rootDirectory.resolvingSymlinksInPath().standardizedFileURL
        let values = try attributes(at: rootDirectory)
        guard values?[.type] as? FileAttributeType == .typeDirectory,
              (values?[.posixPermissions] as? NSNumber)?.intValue == 0o700,
              canonicalRoot == nil || canonicalRoot?.path == root.path else {
            throw ReviewTeamError.invalidOutput("Cancellation storage changed or is not private.")
        }
        canonicalRoot = root
        return root
    }

    private func markerURL(runID: String, root: URL) -> URL {
        let digest = SHA256.hash(data: Data(runID.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(digest, isDirectory: false)
    }

    private func validateMarker(_ marker: URL) throws {
        let values = try attributes(at: marker)
        guard values?[.type] as? FileAttributeType == .typeRegular,
              (values?[.referenceCount] as? NSNumber)?.intValue == 1,
              (values?[.size] as? NSNumber)?.intValue == 0 else {
            throw ReviewTeamError.invalidOutput("The saved cancellation receipt is invalid.")
        }
    }

    private func attributes(at url: URL) throws -> [FileAttributeKey: Any]? {
        do {
            return try FileManager.default.attributesOfItem(atPath: url.path)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain &&
            (error.code == CocoaError.fileReadNoSuchFile.rawValue || error.code == CocoaError.fileNoSuchFile.rawValue) {
            return nil
        }
    }
}

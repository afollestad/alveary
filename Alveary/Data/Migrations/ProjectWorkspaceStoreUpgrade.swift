import CoreData
import Darwin
import Foundation
import SwiftData

/// Upgrade a copy, preserving the original SQLite file and companions until the final schema opens.
/// An installation journal makes a crash between replacing the three files recoverable on the next launch.
@MainActor
enum ProjectWorkspaceStoreUpgrade {
    private static let suffixes = ["", "-wal", "-shm"]

    static func open(at storeURL: URL, validateBridge: (URL) throws -> Void = { _ in }) throws -> ModelContainer {
        let files = FileManager.default
        let staging = storeURL.deletingLastPathComponent().appendingPathComponent(".\(storeURL.lastPathComponent)-folder-upgrade")
        let journal = staging.appendingPathComponent("state")
        let backup = staging.appendingPathComponent("original/\(storeURL.lastPathComponent)")
        let upgraded = staging.appendingPathComponent("upgraded/\(storeURL.lastPathComponent)")
        if (try? String(contentsOf: journal, encoding: .utf8)) == "installing" {
            try replaceStore(at: storeURL, from: backup)
            try "restored".write(to: journal, atomically: true, encoding: .utf8)
        }
        guard try hasExistingStore(at: storeURL) else { return try currentContainer(at: storeURL) }
        // Even a read-only SQLite metadata probe may rewrite shared-memory bytes. Probe an APFS clone
        // so every failure before installation leaves all three original files byte-for-byte intact.
        let inspection = storeURL.deletingLastPathComponent().appendingPathComponent(".store-inspection-\(UUID().uuidString)")
        let inspectedStore = inspection.appendingPathComponent(storeURL.lastPathComponent)
        defer { try? files.removeItem(at: inspection) }
        try copyStore(from: storeURL, to: inspectedStore)
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType, at: inspectedStore, options: [NSReadOnlyPersistentStoreOption: true]
        )
        let versions = metadata[NSStoreModelVersionIdentifiersKey] as? [String] ?? []
        try validateStoreVersions(versions)
        if versions.contains("3.0.0") { return try currentContainer(at: storeURL) }

        if files.fileExists(atPath: staging.path) { try files.removeItem(at: staging) }
        try copyStore(from: storeURL, to: backup)
        try copyStore(from: backup, to: upgraded)
        try autoreleasepool {
            let bridge = try ModelContainer(
                for: Schema(versionedSchema: ProjectWorkspaceBridgeSchema.self), configurations: .init(url: upgraded)
            )
            try ProjectWorkspaceBridgeSchema.backfill(in: bridge.mainContext)
        }
        try validateBridge(upgraded)
        try autoreleasepool {
            _ = try ModelContainer(
                for: Schema(versionedSchema: AlvearySchema.self), migrationPlan: ProjectWorkspaceMigrationPlan.self,
                configurations: .init(url: upgraded)
            )
        }
        try "installing".write(to: journal, atomically: true, encoding: .utf8)
        do {
            try replaceStore(at: storeURL, from: upgraded)
            let container = try currentContainer(at: storeURL)
            try "complete".write(to: journal, atomically: true, encoding: .utf8)
            // The original remains available in the upgrade folder; only the disposable migrated copy is removed.
            try? files.removeItem(at: upgraded.deletingLastPathComponent())
            return container
        } catch {
            try replaceStore(at: storeURL, from: backup)
            try "restored".write(to: journal, atomically: true, encoding: .utf8)
            throw error
        }
    }

    /// A newer app's store must never be inferred back into an older schema.
    static func validateStoreVersions(_ versions: [String]) throws {
        let supported = Set(["", "0.0.0", "1.0.0", "2.0.0", "3.0.0"])
        let unsupported = versions.filter { !supported.contains($0) }
        guard unsupported.isEmpty else { throw UpgradeError.unsupportedVersion(unsupported.joined(separator: ", ")) }
    }

    enum UpgradeError: LocalizedError {
        case unsupportedVersion(String)
        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                "This database uses an unsupported version (\(version)). Open it with the Alveary version that created it or a newer version."
            }
        }
    }

    private static func hasExistingStore(at url: URL) throws -> Bool {
        let files = FileManager.default
        if files.fileExists(atPath: url.path) { return true }
        // Companions are evidence of an existing store, not permission to create a replacement.
        if suffixes.dropFirst().contains(where: { files.fileExists(atPath: url.path + $0) }) {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        return false
    }

    private static func currentContainer(at url: URL) throws -> ModelContainer {
        try ModelContainer(for: Schema(versionedSchema: AlvearySchema.self), configurations: .init(url: url))
    }

    private static func copyStore(from source: URL, to destination: URL) throws {
        let files = FileManager.default
        try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        for suffix in suffixes {
            let input = URL(fileURLWithPath: source.path + suffix)
            if files.fileExists(atPath: input.path) {
                let output = URL(fileURLWithPath: destination.path + suffix)
                if clonefile(input.path, output.path, 0) != 0 { try files.copyItem(at: input, to: output) }
            }
        }
    }

    private static func replaceStore(at destination: URL, from source: URL) throws {
        let files = FileManager.default
        guard files.fileExists(atPath: source.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: source.path])
        }
        for suffix in suffixes {
            let output = URL(fileURLWithPath: destination.path + suffix)
            if files.fileExists(atPath: output.path) { try files.removeItem(at: output) }
        }
        try copyStore(from: source, to: destination)
    }
}

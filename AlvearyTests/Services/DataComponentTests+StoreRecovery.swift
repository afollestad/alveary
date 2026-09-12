import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension DataComponentTests {
    func testUnopenableStoreIsPreservedAcrossRetries() throws {
        let root = try makeRecoveryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = DataComponent.persistentStoreURL(in: root)
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            try Data("not a database \(suffix)".utf8).write(to: URL(fileURLWithPath: storeURL.path + suffix))
        }
        let originals = try storeBytes(at: storeURL)
        for _ in 0..<2 {
            XCTAssertThrowsError(try DataComponent.openModelContainer(isStoredInMemoryOnly: false, persistentStoreURL: storeURL))
            XCTAssertEqual(try storeBytes(at: storeURL), originals)
        }
    }

    func testMissingDatabaseWithSQLiteCompanionsDoesNotCreateAnEmptyStore() throws {
        let root = try makeRecoveryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = DataComponent.persistentStoreURL(in: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        for suffix in ["-wal", "-shm"] {
            try Data("existing companion".utf8).write(to: URL(fileURLWithPath: url.path + suffix))
        }
        let originals = try storeBytes(at: url)
        for _ in 0..<2 {
            XCTAssertThrowsError(try DataComponent.openModelContainer(isStoredInMemoryOnly: false, persistentStoreURL: url))
            XCTAssertEqual(try storeBytes(at: url), originals)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testHealthyStoreReopensWithoutSubstitution() throws {
        let root = try makeRecoveryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = DataComponent.persistentStoreURL(in: root)
        let projectID = try autoreleasepool {
            let container = try DataComponent.openModelContainer(isStoredInMemoryOnly: false, persistentStoreURL: url)
            let project = Project(name: "Empty project")
            container.mainContext.insert(project)
            try container.mainContext.save()
            return project.id
        }
        let reopened = try DataComponent.openModelContainer(isStoredInMemoryOnly: false, persistentStoreURL: url)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<Project>()).map(\.id), [projectID])
    }

    func testInMemoryContainerDoesNotTouchPersistentStore() throws {
        let root = try makeRecoveryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = DataComponent.persistentStoreURL(in: root)
        _ = try DataComponent.openModelContainer(isStoredInMemoryOnly: true, persistentStoreURL: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func makeRecoveryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ProjectMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func storeBytes(at url: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for suffix in ["", "-wal", "-shm"] {
            let path = URL(fileURLWithPath: url.path + suffix)
            if FileManager.default.fileExists(atPath: path.path) { result[suffix] = try Data(contentsOf: path) }
        }
        return result
    }
}

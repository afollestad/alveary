import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension DataComponentTests {
    func testUnopenableStoreIsMovedAsideAndReported() throws {
        let root = try makeRecoveryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = DataComponent.persistentStoreURL(in: root)
        try writeGarbageStore(at: storeURL, includingSidecars: true)

        _ = DataComponent.makeModelContainer(isStoredInMemoryOnly: false, persistentStoreURL: storeURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
        let recoveredURL = try XCTUnwrap(
            DataComponent.consumeLastRecoveredStoreURL(),
            "Recovery must be reported so the app root can tell the user history was set aside"
        )
        XCTAssertTrue(recoveredURL.lastPathComponent.hasPrefix("Alveary.store.corrupt-"))
        XCTAssertEqual(try Data(contentsOf: recoveredURL), Data("not a database".utf8))

        // The `-wal`/`-shm` companions must travel with the store, or the retry can fail on them.
        // Content is not asserted: the failed open rewrites `-shm` before throwing, and the fresh
        // store then makes its own pair back at the original path.
        for suffix in ["-wal", "-shm"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: recoveredURL.path + suffix),
                "Expected the \(suffix) sidecar to move with the store"
            )
        }
    }

    func testStoreRecoveryIsReportedOnlyOnce() throws {
        let root = try makeRecoveryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = DataComponent.persistentStoreURL(in: root)
        try writeGarbageStore(at: storeURL, includingSidecars: false)

        _ = DataComponent.makeModelContainer(isStoredInMemoryOnly: false, persistentStoreURL: storeURL)

        XCTAssertNotNil(DataComponent.consumeLastRecoveredStoreURL())
        XCTAssertNil(DataComponent.consumeLastRecoveredStoreURL())
    }

    func testHealthyStoreIsLeftAloneAndReportsNoRecovery() throws {
        let root = try makeRecoveryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = DataComponent.persistentStoreURL(in: root)

        _ = DataComponent.makeModelContainer(isStoredInMemoryOnly: false, persistentStoreURL: storeURL)
        XCTAssertNil(DataComponent.consumeLastRecoveredStoreURL())

        _ = DataComponent.makeModelContainer(isStoredInMemoryOnly: false, persistentStoreURL: storeURL)
        XCTAssertNil(DataComponent.consumeLastRecoveredStoreURL())

        let siblings = try FileManager.default.contentsOfDirectory(
            atPath: storeURL.deletingLastPathComponent().path
        )
        XCTAssertFalse(siblings.contains { $0.contains(".corrupt-") })
    }

    func testInMemoryContainerNeverReportsRecovery() throws {
        let root = try makeRecoveryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = DataComponent.makeModelContainer(
            isStoredInMemoryOnly: true,
            persistentStoreURL: DataComponent.persistentStoreURL(in: root)
        )

        XCTAssertNil(DataComponent.consumeLastRecoveredStoreURL())
    }

    private func makeRecoveryRoot() throws -> URL {
        _ = DataComponent.consumeLastRecoveredStoreURL()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DataComponentStoreRecoveryTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeGarbageStore(at storeURL: URL, includingSidecars: Bool) throws {
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not a database".utf8).write(to: storeURL)
        guard includingSidecars else {
            return
        }
        for suffix in ["-wal", "-shm"] {
            try Data("sidecar".utf8).write(to: URL(fileURLWithPath: storeURL.path + suffix))
        }
    }
}

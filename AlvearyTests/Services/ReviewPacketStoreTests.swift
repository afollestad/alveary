import Foundation
import XCTest

@testable import Alveary

final class ReviewPacketStoreTests: XCTestCase {
    func testCreateProducesDistinctReadOnlyLeasesWithStableInputHash() async throws {
        let root = try makeTemporaryDirectory()
        let store = ReviewPacketStore(rootDirectory: root)
        let first = try await store.create(runID: "run/one", files: [
            "changes.diff": Data("diff".utf8),
            "context.json": Data("context".utf8)
        ])
        let second = try await store.create(runID: "run/one", files: [
            "context.json": Data("context".utf8),
            "changes.diff": Data("diff".utf8)
        ])

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.directoryURL, second.directoryURL)
        XCTAssertEqual(first.fileNames, ["changes.diff", "context.json"])
        XCTAssertEqual(first.inputHash, second.inputHash)
        XCTAssertEqual(try permissions(at: root), 0o700)
        XCTAssertEqual(try permissions(at: first.directoryURL.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(try permissions(at: first.directoryURL), 0o500)
        XCTAssertEqual(try permissions(at: try XCTUnwrap(first.fileURL(named: "changes.diff"))), 0o400)

        try await store.remove(first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.directoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.directoryURL.path))
        try await store.remove(runID: "run/one")
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.directoryURL.path))
    }

    func testCreateRejectsPathComponents() async throws {
        let root = try makeTemporaryDirectory()
        let store = ReviewPacketStore(rootDirectory: root)

        do {
            _ = try await store.create(runID: "run", files: ["../changes.diff": Data()])
            XCTFail("Expected invalid file name")
        } catch ReviewPacketStoreError.invalidFileName(let fileName) {
            XCTAssertEqual(fileName, "../changes.diff")
        }
    }

    func testRemoveRejectsRunDirectoryReplacedBySymlink() async throws {
        let root = try makeTemporaryDirectory()
        let store = ReviewPacketStore(rootDirectory: root)
        let lease = try await store.create(runID: "run", files: ["context.json": Data("{}".utf8)])
        let runDirectory = lease.directoryURL.deletingLastPathComponent()
        let escapedRun = root.deletingLastPathComponent()
            .appendingPathComponent("escaped-review-packet-\(UUID().uuidString)", isDirectory: true)
        let escapedLease = escapedRun.appendingPathComponent(lease.id, isDirectory: true)
        try FileManager.default.createDirectory(at: escapedLease, withIntermediateDirectories: true)
        let sentinel = escapedLease.appendingPathComponent("sentinel")
        try Data("keep".utf8).write(to: sentinel)
        addTeardownBlock { try? FileManager.default.removeItem(at: escapedRun) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: lease.directoryURL.path)
        try FileManager.default.removeItem(at: runDirectory)
        try FileManager.default.createSymbolicLink(at: runDirectory, withDestinationURL: escapedRun)

        do {
            try await store.remove(lease)
            XCTFail("Expected path escape rejection")
        } catch let error as ReviewPacketStoreError {
            XCTAssertEqual(error, .pathEscapedRoot)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
    }

    func testRemoveRunRejectsRootDirectoryReplacedBySymlink() async throws {
        let root = try makeTemporaryDirectory()
        let store = ReviewPacketStore(rootDirectory: root)
        let lease = try await store.create(runID: "run", files: ["context.json": Data("{}".utf8)])
        let parent = root.deletingLastPathComponent()
        let originalRoot = parent.appendingPathComponent("original-review-packets-\(UUID().uuidString)", isDirectory: true)
        let outside = parent.appendingPathComponent("outside-review-packets-\(UUID().uuidString)", isDirectory: true)
        let outsideRun = outside.appendingPathComponent(
            lease.directoryURL.deletingLastPathComponent().lastPathComponent,
            isDirectory: true
        )
        try FileManager.default.moveItem(at: root, to: originalRoot)
        try FileManager.default.createDirectory(at: outsideRun, withIntermediateDirectories: true)
        let sentinel = outsideRun.appendingPathComponent("sentinel")
        try Data("keep".utf8).write(to: sentinel)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: outside)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: originalRoot)
            try? FileManager.default.removeItem(at: outside)
        }

        do {
            try await store.remove(runID: "run")
            XCTFail("Expected root identity rejection")
        } catch let error as ReviewPacketStoreError {
            XCTAssertEqual(error, .pathEscapedRoot)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
    }

    func testRemoveRunRejectsDigestDirectoryRedirectedInsideRoot() async throws {
        let root = try makeTemporaryDirectory()
        let store = ReviewPacketStore(rootDirectory: root)
        let first = try await store.create(runID: "run-a", files: ["context.json": Data("a".utf8)])
        let second = try await store.create(runID: "run-b", files: ["context.json": Data("b".utf8)])
        let firstRun = first.directoryURL.deletingLastPathComponent()
        let secondRun = second.directoryURL.deletingLastPathComponent()
        let movedFirstRun = root.deletingLastPathComponent()
            .appendingPathComponent("moved-review-run-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.moveItem(at: firstRun, to: movedFirstRun)
        try FileManager.default.createSymbolicLink(at: firstRun, withDestinationURL: secondRun)
        addTeardownBlock { try? FileManager.default.removeItem(at: movedFirstRun) }

        do {
            try await store.remove(runID: "run-a")
            XCTFail("Expected run identity rejection")
        } catch let error as ReviewPacketStoreError {
            XCTAssertEqual(error, .pathEscapedRoot)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.directoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(second.fileURL(named: "context.json")).path))
    }

    func testLeaseValidationRejectsChangedContents() async throws {
        let root = try makeTemporaryDirectory()
        let store = ReviewPacketStore(rootDirectory: root)
        let lease = try await store.create(runID: "run", files: ["context.json": Data("{}".utf8)])
        let file = try XCTUnwrap(lease.fileURL(named: "context.json"))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: lease.directoryURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        try Data("changed".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: file.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: lease.directoryURL.path)

        XCTAssertThrowsError(try lease.validate()) { error in
            XCTAssertEqual(error as? ReviewPacketStoreError, .invalidLease)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-review-packet-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
    }
}

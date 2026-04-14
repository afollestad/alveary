import Foundation
import XCTest

@testable import Alveary

final class CanonicalPathTests: XCTestCase {
    func testNormalizeResolvesSymlinks() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let targetDirectory = tempDirectory.appendingPathComponent("target", isDirectory: true)
        let symlinkDirectory = tempDirectory.appendingPathComponent("link", isDirectory: true)

        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlinkDirectory, withDestinationURL: targetDirectory)

        XCTAssertEqual(
            CanonicalPath.normalize(symlinkDirectory.path),
            targetDirectory.standardizedFileURL.path
        )
    }

    func testNormalizeIsIdempotent() {
        let normalized = CanonicalPath.normalize("/tmp/../tmp/alveary-project")

        XCTAssertEqual(CanonicalPath.normalize(normalized), normalized)
    }

    func testAbbreviateHomeDirectoryReplacesHomePrefixWithTilde() {
        let homeDirectory = NSHomeDirectory()
        let path = homeDirectory + "/Development/alveary"

        XCTAssertEqual(
            CanonicalPath.abbreviateHomeDirectory(path),
            "~/Development/alveary"
        )
    }

    func testAbbreviateHomeDirectoryKeepsExternalPathsUnchanged() {
        XCTAssertEqual(
            CanonicalPath.abbreviateHomeDirectory("/tmp/alveary"),
            "/tmp/alveary"
        )
    }

    func testNormalizeHandlesNonexistentPaths() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let missingPath = tempDirectory
            .appendingPathComponent("missing")
            .appendingPathComponent("../missing")
            .path

        XCTAssertEqual(
            CanonicalPath.normalize(missingPath),
            tempDirectory.appendingPathComponent("missing").path
        )
    }

    func testNormalizeMentionPathMakesWorkingDirectoryPathsRelative() {
        let workingDirectory = "/tmp/alveary/project"
        let filePath = "/tmp/alveary/project/Alveary/Views/Chat/ChatView.swift"

        XCTAssertEqual(
            CanonicalPath.normalizeMentionPath(filePath, relativeTo: workingDirectory),
            "Alveary/Views/Chat/ChatView.swift"
        )
    }

    func testNormalizeMentionPathKeepsExternalPathsAbsolute() {
        let workingDirectory = "/tmp/alveary/project"
        let filePath = "/tmp/other/External.swift"

        XCTAssertEqual(
            CanonicalPath.normalizeMentionPath(filePath, relativeTo: workingDirectory),
            "/tmp/other/External.swift"
        )
    }

    func testDisplayMentionPathAbbreviatesHomeDirectoryAfterNormalization() {
        let homeDirectory = NSHomeDirectory()
        let workingDirectory = homeDirectory + "/Development/alveary"
        let filePath = homeDirectory + "/Documents/Notes.swift"

        XCTAssertEqual(
            CanonicalPath.displayMentionPath(filePath, relativeTo: workingDirectory),
            "~/Documents/Notes.swift"
        )
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

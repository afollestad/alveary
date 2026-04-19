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

    func testEncodeStoredMentionPathEscapesSpacesAndPercent() {
        XCTAssertEqual(
            CanonicalPath.encodeStoredMentionPath("/Users/me/My File.png"),
            "/Users/me/My%20File.png"
        )
        XCTAssertEqual(
            CanonicalPath.encodeStoredMentionPath("/Users/me/100% done.txt"),
            "/Users/me/100%25%20done.txt"
        )
    }

    func testEncodeStoredMentionPathEscapesNarrowNoBreakSpace() {
        // macOS screenshot filenames use U+202F (narrow no-break space). The mention
        // regex treats it as whitespace, so storage must encode it.
        XCTAssertEqual(
            CanonicalPath.encodeStoredMentionPath("/Users/me/Screenshot\u{202F}PM.png"),
            "/Users/me/Screenshot%E2%80%AFPM.png"
        )
    }

    func testEncodeStoredMentionPathEscapesRegexTerminatorsNotCoveredByUrlPathAllowed() {
        // `)` and `'` are in `urlPathAllowed` but terminate the mention regex.
        XCTAssertEqual(
            CanonicalPath.encodeStoredMentionPath("/tmp/weird(2)'file.txt"),
            "/tmp/weird(2%29%27file.txt"
        )
    }

    func testEncodeDecodeStoredMentionPathRoundTrips() {
        let samples = [
            "/Users/me/Screenshot 2026-04-19 at 6.46.48\u{202F}PM.png",
            "/Users/me/100% done.txt",
            "/tmp/weird(2)'file.txt",
            "/Users/me/ordinary.txt"
        ]
        for sample in samples {
            let roundTripped = CanonicalPath.decodeStoredMentionPath(
                CanonicalPath.encodeStoredMentionPath(sample)
            )
            XCTAssertEqual(roundTripped, sample, "round-trip failed for \(sample)")
        }
    }

    func testNormalizeMentionPathDecodesBeforeNormalizing() {
        let workingDirectory = "/tmp/alveary/project"
        let encodedPath = "/tmp/alveary/project/docs/My%20Notes.md"

        XCTAssertEqual(
            CanonicalPath.normalizeMentionPath(encodedPath, relativeTo: workingDirectory),
            "docs/My Notes.md"
        )
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

import XCTest

@testable import Alveary

@MainActor
final class ChatTranscriptLinkResolutionTests: XCTestCase {
    func testResolvesRelativePathAgainstWorkingDirectory() throws {
        let url = try XCTUnwrap(URL(string: "Alveary/DI/AGENTS.md"))
        let resolved = ChatTranscriptView.resolveMarkdownLinkURL(
            url,
            workingDirectory: "/Users/test/alveary"
        )

        XCTAssertEqual(resolved.scheme, "file")
        XCTAssertEqual(resolved.path, "/Users/test/alveary/Alveary/DI/AGENTS.md")
    }

    func testPassesAbsoluteHTTPSURLThrough() throws {
        let original = try XCTUnwrap(URL(string: "https://example.com/docs"))
        let resolved = ChatTranscriptView.resolveMarkdownLinkURL(
            original,
            workingDirectory: "/Users/test/alveary"
        )

        XCTAssertEqual(resolved, original)
    }

    func testPassesAbsoluteFileURLThrough() throws {
        let original = try XCTUnwrap(URL(string: "file:///Users/test/outside/file.md"))
        let resolved = ChatTranscriptView.resolveMarkdownLinkURL(
            original,
            workingDirectory: "/Users/test/alveary"
        )

        XCTAssertEqual(resolved, original)
    }

    func testReturnsOriginalURLWhenWorkingDirectoryIsNil() throws {
        let original = try XCTUnwrap(URL(string: "Alveary/DI/AGENTS.md"))
        let resolved = ChatTranscriptView.resolveMarkdownLinkURL(
            original,
            workingDirectory: nil
        )

        XCTAssertEqual(resolved, original)
    }

    func testReturnsOriginalURLWhenWorkingDirectoryIsEmpty() throws {
        let original = try XCTUnwrap(URL(string: "Alveary/DI/AGENTS.md"))
        let resolved = ChatTranscriptView.resolveMarkdownLinkURL(
            original,
            workingDirectory: ""
        )

        XCTAssertEqual(resolved, original)
    }

    func testExpandsTildePrefixToHomeDirectoryEvenWithoutWorkingDirectory() throws {
        let url = try XCTUnwrap(URL(string: "~/Desktop/edit-tool-multiple-files.png"))
        let resolved = ChatTranscriptView.resolveMarkdownLinkURL(url, workingDirectory: nil)

        let expectedPath = (("~/Desktop/edit-tool-multiple-files.png") as NSString).expandingTildeInPath
        XCTAssertEqual(resolved.scheme, "file")
        XCTAssertEqual(resolved.path, expectedPath)
    }

    func testTildeExpansionWinsOverWorkingDirectoryResolution() throws {
        let url = try XCTUnwrap(URL(string: "~/Desktop/file.png"))
        let resolved = ChatTranscriptView.resolveMarkdownLinkURL(
            url,
            workingDirectory: "/Users/test/alveary"
        )

        let expectedPath = (("~/Desktop/file.png") as NSString).expandingTildeInPath
        XCTAssertEqual(resolved.scheme, "file")
        XCTAssertEqual(resolved.path, expectedPath)
        XCTAssertFalse(resolved.path.contains("alveary/~"))
    }

    func testTildeExpansionDecodesPercentEncodedSpaces() throws {
        let url = try XCTUnwrap(URL(string: "~/Desktop/my%20file.png"))
        let resolved = ChatTranscriptView.resolveMarkdownLinkURL(url, workingDirectory: nil)

        let expectedPath = (("~/Desktop/my file.png") as NSString).expandingTildeInPath
        XCTAssertEqual(resolved.scheme, "file")
        XCTAssertEqual(resolved.path, expectedPath)
        XCTAssertFalse(resolved.path.contains("%20"))
    }

    func testResolvesPercentEncodedSpacesInRelativePath() throws {
        let url = try XCTUnwrap(URL(string: "sub%20dir/my%20file.md"))
        let resolved = ChatTranscriptView.resolveMarkdownLinkURL(
            url,
            workingDirectory: "/Users/test/alveary"
        )

        XCTAssertEqual(resolved.scheme, "file")
        XCTAssertEqual(resolved.path, "/Users/test/alveary/sub dir/my file.md")
    }

    func testResolvesPathAbsoluteSchemelessURL() throws {
        let url = try XCTUnwrap(URL(string: "/Users/test/outside/file.md"))
        let resolved = ChatTranscriptView.resolveMarkdownLinkURL(
            url,
            workingDirectory: "/Users/test/alveary"
        )

        XCTAssertEqual(resolved.scheme, "file")
        XCTAssertEqual(resolved.path, "/Users/test/outside/file.md")
    }

    func testPassesFragmentOnlyURLThrough() throws {
        let original = try XCTUnwrap(URL(string: "#section"))
        let resolved = ChatTranscriptView.resolveMarkdownLinkURL(
            original,
            workingDirectory: "/Users/test/alveary"
        )

        XCTAssertEqual(resolved, original)
    }
}

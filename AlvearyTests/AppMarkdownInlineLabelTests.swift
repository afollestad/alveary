import XCTest

@testable import Alveary

final class AppMarkdownInlineLabelTests: XCTestCase {
    func testPlainTextReturnsInputUnchangedWhenNoInlineCodeIsPresent() {
        XCTAssertEqual(
            AppMarkdownInlineLabel.plainText(from: "Simple thread name"),
            "Simple thread name"
        )
    }

    func testPlainTextStripsSingleBacktickDelimitersButKeepsCodeContent() {
        XCTAssertEqual(
            AppMarkdownInlineLabel.plainText(from: "Test `code` Rendering"),
            "Test code Rendering"
        )
    }

    func testPlainTextStripsMultiBacktickDelimitersPreservingBothEnds() {
        XCTAssertEqual(
            AppMarkdownInlineLabel.plainText(from: "Start ``inside code`` end"),
            "Start inside code end"
        )
    }

    func testPlainTextHandlesMultipleInlineCodeSpans() {
        XCTAssertEqual(
            AppMarkdownInlineLabel.plainText(from: "`alpha` and `beta` and `gamma`"),
            "alpha and beta and gamma"
        )
    }

    func testPlainTextLeavesUnmatchedBacktickAlone() {
        // No matching closing delimiter, so the parser emits no inline ranges and the
        // original string (including the stray backtick) is returned verbatim.
        XCTAssertEqual(
            AppMarkdownInlineLabel.plainText(from: "Incomplete `span"),
            "Incomplete `span"
        )
    }

    func testPlainTextSurfacesLeadingAtMentionAsChipLabel() {
        XCTAssertEqual(
            AppMarkdownInlineLabel.plainText(from: "@.alveary.json"),
            "@.alveary.json"
        )
    }

    func testPlainTextDecodesPercentEncodedBasenameForAtMention() {
        XCTAssertEqual(
            AppMarkdownInlineLabel.plainText(from: "Fix @/Users/me/My%20File.png please"),
            "Fix @My File.png please"
        )
    }

    func testPlainTextKeepsAtMentionInsideInlineCodeAsCodeContent() {
        // Mention is swallowed by the surrounding inline-code span; inner content is
        // preserved verbatim rather than being re-chipped as a file mention.
        XCTAssertEqual(
            AppMarkdownInlineLabel.plainText(from: "Literal `@not-a-file` text"),
            "Literal @not-a-file text"
        )
    }

    func testPlainTextHandlesMixOfInlineCodeAndAtMention() {
        // Both chip types must co-exist in order without either swallowing the other:
        // the mention sits after the code span and gets decoded to its basename; the
        // code span stays verbatim. Locks in the event-merge + sort in `segments(for:)`.
        XCTAssertEqual(
            AppMarkdownInlineLabel.plainText(from: "Run `ls` on @/Users/me/My%20Docs/notes.md"),
            "Run ls on @notes.md"
        )
    }

    func testPlainTextHandlesMultipleAtMentions() {
        // Two mentions in the same string must both chip independently.
        XCTAssertEqual(
            AppMarkdownInlineLabel.plainText(from: "Compare @foo.swift with @bar.swift"),
            "Compare @foo.swift with @bar.swift"
        )
    }
}

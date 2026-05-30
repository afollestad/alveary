import XCTest

@testable import Alveary

final class AppMarkdownInlineLabelTests: XCTestCase {
    func testPlainTextReturnsInputUnchangedWhenNoInlineCodeIsPresent() {
        XCTAssertEqual(
            AppMarkdownInlineLabel.plainText(from: "Simple thread name"),
            "Simple thread name"
        )
    }

    func testPlainTextStripsMarkdownLinkDelimitersButKeepsLabel() {
        XCTAssertEqual(
            AppMarkdownInlineLabel.plainText(from: "Open [.alveary.json](.alveary.json)"),
            "Open .alveary.json"
        )
    }

    func testPlainTextStripsStrongAndEmphasisDelimiters() {
        XCTAssertEqual(
            AppMarkdownInlineLabel.plainText(from: "**Bold** and *italic*"),
            "Bold and italic"
        )
    }

    func testPlainTextStripsSupportedHTMLInlineDelimiters() {
        XCTAssertEqual(
            AppMarkdownInlineLabel.plainText(from: "<strong>Bold</strong> <em>italic</em> <u>under</u>"),
            "Bold italic under"
        )
    }

    func testPlainTextReplacesHTMLImageTagsWithPlaceholder() {
        XCTAssertEqual(
            AppMarkdownInlineLabel.plainText(from: #"Before <img src="file.png" alt="Diagram" width="120" /> after"#),
            "Before (Image) after"
        )
    }

    func testPlainTextStripsUnsupportedHTMLTags() {
        XCTAssertEqual(
            AppMarkdownInlineLabel.plainText(from: #"<div class="note">Title <span>body</span></div>"#),
            "Title body"
        )
    }

    func testPlainTextDoesNotStripAngleBracketAutolinks() {
        XCTAssertEqual(
            AppMarkdownInlineLabel.plainText(from: "Open <https://example.com>"),
            "Open https://example.com"
        )
    }

    func testPlainTextPreservesHTMLImageTagInsideInlineCode() {
        XCTAssertEqual(
            AppMarkdownInlineLabel.plainText(from: #"`<img src="file.png" />`"#),
            #"<img src="file.png" />"#
        )
    }

    func testPlainTextPreservesHTMLLikeTagsInsideInlineCode() {
        XCTAssertEqual(
            AppMarkdownInlineLabel.plainText(from: "Fix `Array<String>`"),
            "Fix Array<String>"
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
        // code span stays verbatim. Locks in the event-merge + sort in `displaySegments(for:)`.
        XCTAssertEqual(
            AppMarkdownInlineLabel.plainText(from: "Run `ls` on @/Users/me/My%20Docs/notes.md"),
            "Run ls on @notes.md"
        )
    }

    func testPlainTextHandlesMixOfMarkdownLinkInlineCodeAndAtMention() {
        XCTAssertEqual(
            AppMarkdownInlineLabel.plainText(from: "Open [docs](https://example.com), run `ls`, inspect @/tmp/My%20File.md"),
            "Open docs, run ls, inspect @My File.md"
        )
    }

    func testPlainTextKeepsAtMentionInsideMarkdownLinkAsLinkLabelText() {
        XCTAssertEqual(
            AppMarkdownInlineLabel.plainText(from: "See [@/tmp/My%20File.md](https://example.com)"),
            "See @/tmp/My%20File.md"
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

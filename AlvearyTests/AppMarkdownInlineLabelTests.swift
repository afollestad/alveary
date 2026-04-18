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
}

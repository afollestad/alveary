import XCTest

@testable import Alveary

final class ComposerDocumentTests: XCTestCase {
    func testProjectionHidesBlockCodeFencesAndSerializesThemBack() {
        let markdown = "Intro\n```\nlet value = 1\n```\nAfter"
        let document = ComposerDocument(markdown: markdown)

        XCTAssertEqual(document.projection.visibleString, "Intro\nlet value = 1\nAfter")
        XCTAssertFalse(document.projection.visibleString.contains("```"))
        XCTAssertEqual(document.serializedMarkdown, markdown)
    }

    func testTrailingOutsideLineAfterClosedCodeBlockRoundTrips() {
        let markdown = "```\nlet value = 1\n```\n"
        let document = ComposerDocument(markdown: markdown)

        XCTAssertEqual(document.projection.visibleString, "let value = 1\n")
        XCTAssertEqual(document.serializedMarkdown, markdown)
    }

    func testTypingFenceAtStartOfExistingLineMovesLineIntoCodeBlock() throws {
        let document = ComposerDocument(markdown: "let value = 1")
        let result = try XCTUnwrap(ComposerTransaction.replacingVisibleText(
            in: document,
            projection: document.projection,
            range: NSRange(location: 0, length: 0),
            replacement: "```"
        ))

        XCTAssertEqual(result.document.projection.visibleString, "let value = 1")
        XCTAssertEqual(result.document.serializedMarkdown, "```\nlet value = 1")
        XCTAssertEqual(result.selection, NSRange(location: 0, length: 0))
    }

    func testShiftReturnInsideCodeBlockInsertsCodeContentLine() throws {
        let document = ComposerDocument(markdown: "```\nlet value = 1")
        let location = (document.projection.visibleString as NSString).length
        let result = try XCTUnwrap(ComposerTransaction.insertNewline(
            in: document,
            projection: document.projection,
            location: location
        ))

        XCTAssertEqual(result.document.projection.visibleString, "let value = 1\n")
        XCTAssertEqual(result.document.serializedMarkdown, "```\nlet value = 1\n")
        XCTAssertEqual(result.selection, NSRange(location: location + 1, length: 0))
    }

    func testBackspaceBelowCodeBlockMovesIntoBlockWithoutChangingDocument() throws {
        let document = ComposerDocument(markdown: "```\nlet value = 1\n```\n")
        let projection = document.projection
        let newlineRange = NSRange(location: (projection.visibleString as NSString).length - 1, length: 1)
        let result = try XCTUnwrap(ComposerTransaction.replacingVisibleText(
            in: document,
            projection: projection,
            range: newlineRange,
            replacement: ""
        ))

        let codeRange = try XCTUnwrap(projection.codeBlockRanges.first)
        XCTAssertEqual(result.document, document)
        XCTAssertEqual(result.selection, NSRange(location: NSMaxRange(codeRange), length: 0))
    }

    func testOnlyEmptyCodeBlockIsEffectivelyEmpty() {
        XCTAssertTrue(ComposerDocument(markdown: "```\n").isEffectivelyEmpty)
        XCTAssertTrue(ComposerDocument(markdown: "```\n\n").isEffectivelyEmpty)
        XCTAssertFalse(ComposerDocument(markdown: "```\nlet value = 1").isEffectivelyEmpty)
    }
}

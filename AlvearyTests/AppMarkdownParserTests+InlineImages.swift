import BlockInputKit
import Foundation
import XCTest
@testable import Alveary

extension AppMarkdownParserTests {
    func testRemoteInlineImageAttachesAttributeToAltRun() throws {
        let document = AppMarkdownParser()
            .documentPreservingSource(for: "Before ![P1](https://example.com/p1.png) after")

        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertEqual(String(document.content.characters), "Before P1 after")
        let info = try XCTUnwrap(inlineImageInfo(for: "P1", in: document.content))
        XCTAssertEqual(info.source, "https://example.com/p1.png")
        XCTAssertEqual(info.altText, "P1")
        XCTAssertNil(info.width)
        XCTAssertNil(info.height)
    }

    func testRemoteInlineImageInsideBoldKeepsBoldStyling() throws {
        let document = AppMarkdownParser()
            .documentPreservingSource(for: "**![P1](https://example.com/p1.png) Add the trailer** now")

        XCTAssertEqual(String(document.content.characters), "P1 Add the trailer now")
        let info = try XCTUnwrap(inlineImageInfo(for: "P1", in: document.content))
        XCTAssertEqual(info.source, "https://example.com/p1.png")
        let boldRun = document.content.runs.first { run in
            String(document.content[run.range].characters).contains("Add the trailer")
        }
        XCTAssertTrue(boldRun?.inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
    }

    func testRemoteHTMLInlineImageCarriesDeclaredDimensions() throws {
        let document = AppMarkdownParser().documentPreservingSource(
            for: #"Badge <img src="https://example.com/p1.png" alt="P1" width="40" height="20"> alert"#
        )

        XCTAssertEqual(document.blocks.count, 1)
        let info = try XCTUnwrap(inlineImageInfo(for: "P1", in: document.content))
        XCTAssertEqual(info.width, 40)
        XCTAssertEqual(info.height, 20)
    }

    func testRemoteImageAloneOnItsLineStillBecomesImageBlock() throws {
        let document = AppMarkdownParser()
            .documentPreservingSource(for: "Text\n\n![Alt](https://example.com/image.png)\n\nMore")

        XCTAssertEqual(document.blocks.count, 3)
        guard case let .image(block) = document.blocks[1] else {
            return XCTFail("Expected an image block at index 1.")
        }
        XCTAssertEqual(block.image, BlockInputImage(source: "https://example.com/image.png", altText: "Alt"))
    }

    func testMultipleInlineImagesAttachInOrder() throws {
        let document = AppMarkdownParser().documentPreservingSource(
            for: "One ![A](https://example.com/a.png) two ![B](https://example.com/b.png) three"
        )

        XCTAssertEqual(String(document.content.characters), "One A two B three")
        XCTAssertEqual(inlineImageInfo(for: "A", in: document.content)?.source, "https://example.com/a.png")
        XCTAssertEqual(inlineImageInfo(for: "B", in: document.content)?.source, "https://example.com/b.png")
    }

    func testInlineParsingModeKeepsPlainAltFallback() throws {
        let attributed = try AppMarkdownParser(parsingMode: .inline)
            .attributedString(for: "Before ![P1](https://example.com/p1.png) after")

        XCTAssertEqual(String(attributed.characters), "Before P1 after")
        XCTAssertNil(inlineImageInfo(for: "P1", in: attributed))
    }

    func testInlineImageSyntaxInsideInlineCodeStaysLiteral() throws {
        let attributed = try AppMarkdownParser()
            .attributedString(for: "Use `x ![P1](https://example.com/p1.png)` verbatim")

        XCTAssertTrue(String(attributed.characters).contains("![P1](https://example.com/p1.png)"))
        XCTAssertNil(inlineImageInfo(for: "P1", in: attributed))
    }

    private func inlineImageInfo(
        for text: String,
        in attributed: AttributedString
    ) -> AppMarkdownInlineImageInfo? {
        for run in attributed.runs[AppMarkdownInlineImageAttribute.self] {
            guard let info = run.0 else {
                continue
            }
            if String(attributed[run.1].characters) == text {
                return info
            }
        }
        return nil
    }
}

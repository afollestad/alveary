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

    func testTableCellHoldingOnlyALinkedImageResolvesToACellImage() throws {
        let document = AppMarkdownParser().documentPreservingSource(for: Self.beforeAfterTableMarkdown)
        let cellImages = tableCells(in: document).compactMap(\.appMarkdownSoleInlineImage)

        XCTAssertEqual(cellImages.count, 2)
        let before = try XCTUnwrap(cellImages.first)
        XCTAssertEqual(before.image.source, "https://example.com/before.png")
        XCTAssertEqual(before.image.altText, "Before")
        // The wrapper link is what a click follows, so it has to survive the cell round trip.
        XCTAssertEqual(before.link, URL(string: "https://example.com/before.mp4"))
    }

    func testTableCellCarryingTextIsNotACellImage() throws {
        let document = AppMarkdownParser().documentPreservingSource(for: Self.beforeAfterTableMarkdown)
        let textCells = tableCells(in: document).filter { $0.appMarkdownSoleInlineImage == nil }

        // Both header cells and both build-link cells stay inline text.
        XCTAssertEqual(textCells.count, 4)

        let mixed = AppMarkdownParser()
            .documentPreservingSource(for: "Shipped ![P1](https://example.com/p1.png)")
        XCTAssertNil(mixed.content.appMarkdownSoleInlineImage)
    }

    func testInlineImageDisplaySizeFitsTheInlineCap() {
        let info = AppMarkdownInlineImageInfo(
            image: BlockInputImage(source: "https://example.com/tall.png", altText: "Tall")
        )

        let badge = info.displaySize(forNaturalSize: CGSize(width: 40, height: 20))
        XCTAssertEqual(badge, CGSize(width: 40, height: 20))

        // A phone capture inline: scaled into the cap instead of sizing at 720x1565.
        let capture = info.displaySize(forNaturalSize: CGSize(width: 720, height: 1_565))
        XCTAssertLessThanOrEqual(capture.width, appMarkdownInlineImageMaxSize.width)
        XCTAssertLessThanOrEqual(capture.height, appMarkdownInlineImageMaxSize.height)
        XCTAssertEqual(capture.width / capture.height, 720.0 / 1_565.0, accuracy: 0.01)
    }

    func testBaselineDropCentersBadgesAndClampsPictures() {
        let capHeight: CGFloat = 9

        // Unchanged for a badge: it still centers on the cap-height midline.
        XCTAssertEqual(
            AppMarkdownInlineImageInfo.baselineDrop(forDisplayHeight: 20, capHeight: capHeight),
            5.5,
            accuracy: 0.01
        )
        // Clamped for a picture. Unclamped this is ~778pt, all of which renders as blank space
        // above the image because the drop is descent added on top of the image's full ascent.
        XCTAssertEqual(
            AppMarkdownInlineImageInfo.baselineDrop(forDisplayHeight: 1_565, capHeight: capHeight),
            capHeight,
            accuracy: 0.01
        )
    }

    private static let beforeAfterTableMarkdown = """
    | Before | After |
    | --- | --- |
    | [![Before](https://example.com/before.png)](https://example.com/before.mp4) | \
    [![After](https://example.com/after.png)](https://example.com/after.mp4) |
    | Build #26 | Build #99199 |
    """

    /// Every cell of the document's single table, in row-major order.
    private func tableCells(in document: AppMarkdownDocument) -> [AttributedString] {
        document.content.appMarkdownBlockRuns(parent: nil).flatMap { tableRun -> [AttributedString] in
            let tableContent = document.content[tableRun.range]
            return tableContent.appMarkdownBlockRuns(parent: tableRun.intent).flatMap { rowRun in
                let rowContent = tableContent[rowRun.range]
                return rowContent.appMarkdownBlockRuns(parent: rowRun.intent).map { cellRun in
                    AttributedString(rowContent[cellRun.range])
                }
            }
        }
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

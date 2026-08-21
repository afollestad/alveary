import XCTest

@testable import Alveary

/// `<details>` disclosures: how the parser lifts them into document blocks, and how it falls back
/// to flattened text when it cannot.
extension AppMarkdownParserTests {
    func testExtractsDetailsBlockWithSummaryAndBody() throws {
        let document = try AppMarkdownParser().document(
            for: "Intro\n\n<details><summary>Test run logs</summary>\n\nBody text\n\n</details>"
        )

        XCTAssertEqual(document.blocks.count, 2)
        guard case .details(let details) = document.blocks[1] else {
            return XCTFail("Expected a details block, got \(document.blocks[1])")
        }
        XCTAssertEqual(String(details.summary.characters), "Test run logs")
        XCTAssertFalse(details.isInitiallyOpen)
        XCTAssertEqual(details.blocks.count, 1)
        XCTAssertEqual(plainText(of: details.blocks[0]), "Body text")
    }

    func testHonorsTheOpenAttribute() throws {
        let open = try AppMarkdownParser().document(for: "<details open><summary>S</summary>body</details>")
        let quoted = try AppMarkdownParser().document(for: "<details open=\"open\"><summary>S</summary>body</details>")
        let denied = try AppMarkdownParser().document(for: "<details open=\"false\"><summary>S</summary>body</details>")

        XCTAssertEqual(detailsBlock(in: open)?.isInitiallyOpen, true)
        XCTAssertEqual(detailsBlock(in: quoted)?.isInitiallyOpen, true)
        XCTAssertEqual(detailsBlock(in: denied)?.isInitiallyOpen, false)
    }

    /// `open` has to be its own attribute. Matching it as a bare substring also fires inside
    /// `data-open` and quoted values, expanding disclosures their author left shut.
    func testDoesNotTreatOtherAttributesAsTheOpenAttribute() throws {
        let classed = try AppMarkdownParser().document(
            for: "<details class=\"open-section\"><summary>S</summary>body</details>"
        )
        let identified = try AppMarkdownParser().document(
            for: "<details id=\"open\"><summary>S</summary>body</details>"
        )

        XCTAssertEqual(detailsBlock(in: classed)?.isInitiallyOpen, false)
        XCTAssertEqual(detailsBlock(in: identified)?.isInitiallyOpen, false)
    }

    func testFallsBackToDefaultSummaryWhenNoneIsDeclared() throws {
        let document = try AppMarkdownParser().document(for: "<details>body</details>")

        XCTAssertEqual(
            detailsBlock(in: document).map { String($0.summary.characters) },
            AppMarkdownDetailsSyntaxParser.defaultSummary
        )
    }

    func testNestsDetailsBlocksAndKeepsTheOuterSummary() throws {
        let document = try AppMarkdownParser().document(
            for: """
            <details><summary>Outer</summary>

            <details><summary>Inner</summary>

            deep

            </details>

            </details>
            """
        )

        let outer = try XCTUnwrap(detailsBlock(in: document))
        XCTAssertEqual(String(outer.summary.characters), "Outer")
        XCTAssertEqual(outer.blocks.count, 1)
        guard case .details(let inner) = outer.blocks[0] else {
            return XCTFail("Expected a nested details block, got \(outer.blocks[0])")
        }
        XCTAssertEqual(String(inner.summary.characters), "Inner")
    }

    /// A parent with no summary of its own must not adopt its first child's.
    func testNestedSummaryDoesNotBecomeTheParentSummary() throws {
        let document = try AppMarkdownParser().document(
            for: "<details>\n\n<details><summary>Inner</summary>deep</details>\n\n</details>"
        )

        XCTAssertEqual(
            detailsBlock(in: document).map { String($0.summary.characters) },
            AppMarkdownDetailsSyntaxParser.defaultSummary
        )
    }

    func testExtractsImagesInsideADetailsBody() throws {
        let document = try AppMarkdownParser().document(
            for: "<details><summary>Shots</summary>\n\n![alt](https://example.com/a.png)\n\n</details>"
        )

        let details = try XCTUnwrap(detailsBlock(in: document))
        XCTAssertTrue(
            details.blocks.contains { block in
                if case .image = block {
                    return true
                }
                return false
            },
            "Expected the image inside the disclosure to become an image block, got \(details.blocks)"
        )
    }

    func testLeavesDetailsInsideFencedCodeAlone() throws {
        let document = try AppMarkdownParser().document(
            for: "```html\n<details><summary>kept</summary>\n</details>\n```"
        )

        XCTAssertNil(detailsBlock(in: document))
        XCTAssertTrue(plainText(of: document.blocks[0]).contains("<details>"))
    }

    /// An unclosed disclosure must not swallow the rest of the document; it falls through to the
    /// flattened text path, where the summary becomes a bold line.
    func testUnclosedDetailsFallsBackToFlattenedText() throws {
        let document = try AppMarkdownParser().document(for: "<details><summary>Broken</summary>\n\ntail text")

        XCTAssertNil(detailsBlock(in: document))
        let text = document.blocks.map(plainText(of:)).joined(separator: "\n")
        XCTAssertTrue(text.contains("Broken"), "Expected the summary to survive, got \(text)")
        XCTAssertTrue(text.contains("tail text"), "Expected the tail to survive, got \(text)")
        XCTAssertFalse(text.contains("<details"), "Expected the raw tag to be gone, got \(text)")
    }

    /// The flat `content` string is what surfaces that ignore `blocks` render, so it must never
    /// show raw markup.
    func testFlatContentFlattensDetailsRatherThanPrintingTags() throws {
        let content = try AppMarkdownParser().attributedString(
            for: "<details><summary>Logs</summary>\n\nbody\n\n</details>"
        )

        let text = String(content.characters)
        XCTAssertFalse(text.contains("<details"), text)
        XCTAssertFalse(text.contains("<summary"), text)
        XCTAssertTrue(text.contains("Logs"), text)
        XCTAssertTrue(text.contains("body"), text)
    }

    func testRewritesBreakTagsAsHardLineBreaks() throws {
        let content = try AppMarkdownParser().attributedString(for: "first<br>second")

        let text = String(content.characters)
        XCTAssertFalse(text.contains("<br"), text)
        XCTAssertTrue(text.contains("first"), text)
        XCTAssertTrue(text.contains("second"), text)
    }

    // MARK: - `<section>`

    /// A bot imitating GitHub's footnote footer writes `<section>`, not `<details>`. Left
    /// unclaimed it printed its own tags around the body.
    func testSectionBecomesACollapsedDisclosure() throws {
        let document = try AppMarkdownParser().document(
            for: "Verdict\n\n<section data-footnotes=\"\" class=\"footnotes\">\nReviewed abc123\n</section>"
        )

        let details = try XCTUnwrap(detailsBlock(in: document))
        XCTAssertFalse(details.isInitiallyOpen)
        XCTAssertEqual(String(details.summary.characters), "Footnotes")
        XCTAssertEqual(details.blocks.map(plainText(of:)), ["Reviewed abc123"])
        XCTAssertFalse(document.blocks.map(plainText(of:)).joined().contains("<section"))
    }

    /// `AppMarkdownDocument.content` is what every inline surface renders instead of the blocks,
    /// so a tag the splitter lifts must be flattened there rather than left to print itself.
    func testFlatContentFlattensSectionRatherThanPrintingTags() throws {
        let document = try AppMarkdownParser().document(
            for: "<section class=\"footnotes\">Reviewed abc123</section>"
        )

        let flat = String(document.content.characters)
        XCTAssertFalse(flat.contains("<section"), flat)
        XCTAssertFalse(flat.contains("</section>"), flat)
        XCTAssertTrue(flat.contains("Reviewed abc123"), flat)
    }

    func testSectionSummaryPrefersAriaLabel() throws {
        let document = try AppMarkdownParser().document(
            for: "<section class=\"footnotes\" aria-label=\"Review footer\">body</section>"
        )

        XCTAssertEqual(detailsBlock(in: document).map { String($0.summary.characters) }, "Review footer")
    }

    /// A list of styling classes is not a title, so it falls through rather than guessing which
    /// of them names the section.
    func testSectionWithSeveralClassesUsesTheDefaultSummary() throws {
        let document = try AppMarkdownParser().document(
            for: "<section class=\"footnotes small muted\">body</section>"
        )

        XCTAssertEqual(detailsBlock(in: document).map { String($0.summary.characters) }, "Details")
    }

    func testNestsADetailsInsideASection() throws {
        let document = try AppMarkdownParser().document(
            for: "<section class=\"wrap\"><details><summary>Inner</summary>\n\nlog line\n\n</details></section>"
        )

        let outer = try XCTUnwrap(detailsBlock(in: document))
        XCTAssertEqual(String(outer.summary.characters), "Wrap")
        XCTAssertEqual(outer.blocks.count, 1)
        guard case .details(let inner) = outer.blocks[0] else {
            return XCTFail("Expected a nested details block, got \(outer.blocks[0])")
        }
        XCTAssertEqual(String(inner.summary.characters), "Inner")
        XCTAssertEqual(inner.blocks.map(plainText(of:)), ["log line"])
    }

    /// Pairing by position alone would let a `</section>` close an open `<details>` and invent a
    /// disclosure spanning markup its author never wrapped.
    func testClosingSectionCannotCloseADetails() throws {
        let document = try AppMarkdownParser().document(for: "<details><summary>S</summary>body</section>")

        XCTAssertNil(detailsBlock(in: document))
    }

    /// A bot pretty-prints its wrapper's contents; once the wrapper is lifted, those columns read
    /// as an indented code block and box the body in monospace.
    func testDedentsAWhollyIndentedDisclosureBody() throws {
        let document = try AppMarkdownParser().document(
            for: "<section class=\"footnotes\">\n    Reviewed abc123\n    Iterate locally\n</section>"
        )

        let details = try XCTUnwrap(detailsBlock(in: document))
        let body = try XCTUnwrap(details.blocks.first)
        guard case .markdown(let content) = body else {
            return XCTFail("Expected a markdown block, got \(body)")
        }
        XCTAssertEqual(plainText(of: body), "Reviewed abc123 Iterate locally")
        XCTAssertFalse(
            content.runs.contains { run in
                run.presentationIntent?.components.contains { component in
                    if case .codeBlock = component.kind { return true }
                    return false
                } == true
            },
            "The body must not be read as an indented code block"
        )
    }

    /// Dedenting by the *minimum* is what protects a body that meant its indentation: the prose
    /// sits at column zero, so nothing moves and the code block survives.
    func testKeepsAnIndentedCodeBlockInsideADisclosure() throws {
        let document = try AppMarkdownParser().document(
            for: "<details><summary>S</summary>\n\nprose\n\n    indented code\n\n</details>"
        )

        let details = try XCTUnwrap(detailsBlock(in: document))
        let text = details.blocks.map(plainText(of:)).joined(separator: "\n")
        XCTAssertTrue(text.contains("indented code"), text)
        XCTAssertTrue(text.contains("prose"), text)
    }

    private func detailsBlock(in document: AppMarkdownDocument) -> AppMarkdownDetailsBlock? {
        document.blocks.compactMap { block -> AppMarkdownDetailsBlock? in
            guard case .details(let details) = block else {
                return nil
            }
            return details
        }
        .first
    }

    private func plainText(of block: AppMarkdownDocumentBlock) -> String {
        guard case .markdown(let content) = block else {
            return ""
        }
        return String(content.characters).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

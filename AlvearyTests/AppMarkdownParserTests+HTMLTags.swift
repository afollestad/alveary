import XCTest

@testable import Alveary

/// The HTML tags markdown cannot express: which ones are dropped, what survives the drop, and the
/// prose that must not be mistaken for a tag at all.
extension AppMarkdownParserTests {
    func testDropsUnhandledBlockTagsKeepingTheirText() throws {
        let document = try AppMarkdownParser().document(for: "<div class=\"wrap\">wrapped body</div>")

        XCTAssertEqual(documentText(document), "wrapped body")
    }

    /// `<pre>` used to print its own tags. It joins the drop rather than becoming a fence, because
    /// the pull request sanitizer has already turned any `<code>` inside it into backticks.
    func testDropsPreTagsKeepingTheirText() throws {
        let document = try AppMarkdownParser().document(for: "<pre>keep</pre>")

        XCTAssertEqual(documentText(document), "keep")
    }

    func testDropsUnhandledInlineTagsKeepingTheirText() throws {
        let document = try AppMarkdownParser().document(for: "Press <kbd>Cmd</kbd> then <span>go</span>")

        XCTAssertEqual(documentText(document), "Press Cmd then go")
    }

    /// A `</?[a-z][^>]*>` catch-all also matches these, and deleting them loses content instead of
    /// preserving it. Only named HTML elements are dropped.
    func testLeavesGenericsAndUnknownTagsAlone() throws {
        let document = try AppMarkdownParser().document(for: "Takes Array<String> and Vec<T> plus <Foo> too")

        XCTAssertEqual(documentText(document), "Takes Array<String> and Vec<T> plus <Foo> too")
    }

    func testLeavesTagsInsideFencedCodeAlone() throws {
        let document = try AppMarkdownParser().document(for: "```html\n<div>kept</div>\n```")

        XCTAssertTrue(documentText(document).contains("<div>kept</div>"), documentText(document))
    }

    func testLeavesTagsInsideInlineCodeAlone() throws {
        let document = try AppMarkdownParser().document(for: "Write `<span>` to wrap it")

        XCTAssertEqual(documentText(document), "Write <span> to wrap it")
    }

    func testRewritesCodeTagsAsInlineCode() throws {
        let document = try AppMarkdownParser().document(for: "Run <code>sq agents review</code> locally")

        XCTAssertEqual(documentText(document), "Run sq agents review locally")
        XCTAssertTrue(
            content(of: document).runs.contains { $0.inlinePresentationIntent?.contains(.code) == true },
            "The rewritten span must carry inline-code intent"
        )
    }

    /// `<img>` must not reach the tag drop: it is void, so dropping it would delete the picture
    /// rather than keep anything. `AppMarkdownImages` claims it first.
    func testTurnsImageTagsIntoImagesRatherThanDroppingThem() throws {
        let document = try AppMarkdownParser().document(for: "<img src=\"diagram.png\" alt=\"Diagram\">")

        XCTAssertEqual(document.blocks.count, 1)
        guard case .image(let image) = document.blocks[0] else {
            return XCTFail("Expected an image block, got \(document.blocks[0])")
        }
        XCTAssertEqual(image.image.source, "diagram.png")
        XCTAssertEqual(image.image.altText, "Diagram")
    }

    /// Foundation's parser decodes entities in prose; it does not inside a code span. This pins the
    /// prose half, which is what the `<section>` footer's `&nbsp;` separators land in.
    func testDecodesHTMLEntitiesInProse() throws {
        let document = try AppMarkdownParser().document(for: "one&nbsp;&bull;&nbsp;two &amp; three")

        XCTAssertEqual(documentText(document), "one\u{00A0}\u{2022}\u{00A0}two & three")
    }

    private func content(of document: AppMarkdownDocument) -> AttributedString {
        document.content
    }

    private func documentText(_ document: AppMarkdownDocument) -> String {
        String(document.content.characters).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

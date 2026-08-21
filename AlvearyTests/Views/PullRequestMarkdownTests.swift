import XCTest

@testable import Alveary

final class PullRequestMarkdownTests: XCTestCase {
    func testRewritesDetailsSummaryAndParagraphTags() {
        let input = "Cheers\n<details><summary>Test run logs</summary>\n<p>\nBody text\n</p></details>"

        let output = PullRequestMarkdown.sanitized(input)

        XCTAssertEqual(output, "Cheers\n\n**Test run logs**\n\nBody text")
    }

    /// The `builderbot-code-review` footer, verbatim. Every defect it used to draw is asserted
    /// away here: its own tags as text, its indented body boxed as a code block, and the raw
    /// `&nbsp;` that only survived because of the box.
    func testBotFootnoteSectionBecomesOneCollapsedDisclosure() throws {
        let sanitized = PullRequestMarkdown.sanitized(
            """
            <section data-footnotes="" class="footnotes">
              <p dir="auto">
                <br>
                Reviewed <a href="https://github.com/o/r/commit/190644c">190644c</a> \
            (<a href="https://example.com/run">process</a>)
                &nbsp;•&nbsp;
                Give feedback in <a href="http://go/slack/channels/ai-pr-approvals">#ai-pr-approvals</a>
                &nbsp;•&nbsp;
                Iterate locally with <code>sq agents review</code>
              </p>
            </section>
            """
        )

        let document = try AppMarkdownParser().document(for: sanitized)

        XCTAssertEqual(document.blocks.count, 1)
        guard case .details(let details) = document.blocks[0] else {
            return XCTFail("Expected a details block, got \(document.blocks)")
        }
        XCTAssertEqual(String(details.summary.characters), "Footnotes")
        XCTAssertFalse(details.isInitiallyOpen)

        XCTAssertEqual(details.blocks.count, 1)
        guard case .markdown(let body) = details.blocks[0] else {
            return XCTFail("Expected one markdown body block, got \(details.blocks)")
        }
        let text = String(body.characters)
        XCTAssertTrue(text.contains("Reviewed 190644c (process)"), text)
        XCTAssertTrue(text.contains("Iterate locally with sq agents review"), text)
        XCTAssertFalse(text.contains("<section"), text)
        XCTAssertFalse(text.contains("&nbsp;"), text)
        XCTAssertTrue(text.contains("\u{00A0}\u{2022}\u{00A0}"), text)
        XCTAssertFalse(
            body.runs.contains { run in
                run.presentationIntent?.components.contains { component in
                    if case .codeBlock = component.kind { return true }
                    return false
                } == true
            },
            "The footer must not be read as an indented code block"
        )
        XCTAssertTrue(body.runs.contains { $0.link?.absoluteString.contains("190644c") == true })
    }

    func testRewritesInlineFormattingTags() {
        XCTAssertEqual(
            PullRequestMarkdown.sanitized("<b>bold</b> and <em>italic</em> and <code>code</code><br>next"),
            "**bold** and *italic* and `code`\nnext"
        )
    }

    func testStripsSubAndSupTagsKeepingContent() {
        XCTAssertEqual(
            PullRequestMarkdown.sanitized("<sub><sub>P1 Badge</sub></sub>  **Add the trailer**"),
            "P1 Badge  **Add the trailer**"
        )
        XCTAssertEqual(PullRequestMarkdown.sanitized("x<sup>2</sup>"), "x2")
    }

    func testStripsHTMLComments() {
        XCTAssertEqual(
            PullRequestMarkdown.sanitized("before\n<!-- hidden\nnote -->\nafter"),
            "before\n\nafter"
        )
    }

    func testLeavesFencedCodeBlocksUntouched() {
        let input = "Intro <b>x</b>\n```html\n<details><summary>kept</summary>\n```\nOutro <br>"

        let output = PullRequestMarkdown.sanitized(input)

        XCTAssertEqual(output, "Intro **x**\n```html\n<details><summary>kept</summary>\n```\nOutro")
    }

    func testPreservesPreTagContentDistinctFromParagraphs() {
        // `<p...>` matching must not swallow `<pre>`.
        XCTAssertEqual(
            PullRequestMarkdown.sanitized("<pre>keep</pre>"),
            "<pre>keep</pre>"
        )
    }
}

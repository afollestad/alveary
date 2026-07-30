import XCTest

@testable import Alveary

final class PullRequestMarkdownTests: XCTestCase {
    func testRewritesDetailsSummaryAndParagraphTags() {
        let input = "Cheers\n<details><summary>Test run logs</summary>\n<p>\nBody text\n</p></details>"

        let output = PullRequestMarkdown.sanitized(input)

        XCTAssertEqual(output, "Cheers\n\n**Test run logs**\n\nBody text")
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

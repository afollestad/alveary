import XCTest

@testable import Alveary

final class PullRequestMarkdownTests: XCTestCase {
    /// The sanitizer used to flatten a disclosure into a bold summary above an always-visible
    /// body. It now leaves the tags for the markdown layer, which renders a real collapsible
    /// block; rewriting them here would reopen every section its author chose to collapse.
    func testPassesDetailsAndSummaryThroughWhileRewritingParagraphs() {
        let input = "Cheers\n<details><summary>Test run logs</summary>\n<p>\nBody text\n</p></details>"

        let output = PullRequestMarkdown.sanitized(input)

        // `Cheers` picks up the two-space hard break every non-final prose line gets.
        XCTAssertEqual(output, "Cheers  \n<details><summary>Test run logs</summary>\n\nBody text\n\n</details>")
    }

    /// The sanitized string is what every pull request surface hands the renderer, so the round
    /// trip is what proves the pane actually gets a disclosure.
    func testSanitizedDetailsSurviveIntoACollapsibleBlock() throws {
        let sanitized = PullRequestMarkdown.sanitized(
            "<details><summary>Test run logs</summary>\n\nBody text\n\n</details>"
        )

        let document = try AppMarkdownParser().document(for: sanitized)

        guard case .details(let details) = document.blocks.first else {
            return XCTFail("Expected a details block, got \(document.blocks)")
        }
        XCTAssertEqual(String(details.summary.characters), "Test run logs")
        XCTAssertFalse(details.isInitiallyOpen)
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
            "**bold** and *italic* and `code`  \nnext"
        )
    }

    /// GitHub renders comment bodies with hard breaks on, so consecutive prose lines must not
    /// reflow into one wrapped paragraph. owner-owl's `r:`/`cc:` footer is the case that drove it.
    func testMarksConsecutiveProseLinesAsHardBreaks() {
        XCTAssertEqual(
            PullRequestMarkdown.sanitized("r: @octocat\ncc: @hubot\nthanks"),
            "r: @octocat  \ncc: @hubot  \nthanks"
        )
    }

    func testLeavesBlankLineSeparatedParagraphsAlone() {
        XCTAssertEqual(
            PullRequestMarkdown.sanitized("First paragraph.\n\nSecond paragraph."),
            "First paragraph.\n\nSecond paragraph."
        )
    }

    func testDoesNotDoubleAnExistingHardBreak() {
        XCTAssertEqual(
            PullRequestMarkdown.sanitized("already  \nbroken\\\nalso broken\nend"),
            "already  \nbroken\\\nalso broken  \nend"
        )
    }

    func testHardBreaksDoNotReachFencedCode() {
        XCTAssertEqual(
            PullRequestMarkdown.sanitized("```\nlet a = 1\nlet b = 2\n```"),
            "```\nlet a = 1\nlet b = 2\n```"
        )
    }

    /// A quote's blank separator line is `>`, which is not blank by the sanitizer's reckoning and so
    /// picks up the marker too. `>  ` has to stay a blank quote line, or an alert's multi-block body
    /// collapses into one paragraph.
    func testHardBreaksKeepAnAlertsBlockBodySeparated() throws {
        let sanitized = PullRequestMarkdown.sanitized("> [!NOTE]\n> Lead paragraph.\n>\n> - First\n> - Second")

        let document = AppMarkdownParser().documentPreservingSource(for: sanitized)
        let quote = try XCTUnwrap(document.content.appMarkdownBlockRuns(parent: nil).first)
        let alert = try XCTUnwrap(AppMarkdownAlert(content: AttributedString(document.content[quote.range])))
        let kinds = alert.contentWithoutMarker
            .appMarkdownBlockRuns(parent: quote.intent)
            .compactMap(\.intent?.kind)

        guard kinds.count == 2, case .paragraph = kinds[0], case .unorderedList = kinds[1] else {
            return XCTFail("Expected a paragraph then an unordered list, got \(kinds)")
        }
    }

    /// A table's rows, delimiter row, and list items all still parse as themselves with the marker
    /// appended — the marker is only meaningful inside a paragraph.
    func testHardBreaksLeaveTablesAndListsParsing() throws {
        let sanitized = PullRequestMarkdown.sanitized("| A | B |\n| --- | --- |\n| 1 | 2 |\n\n- one\n- two")

        let document = AppMarkdownParser().documentPreservingSource(for: sanitized)
        let kinds = document.content.appMarkdownBlockRuns(parent: nil).compactMap(\.intent?.kind)

        guard kinds.count == 2, case .table = kinds[0], case .unorderedList = kinds[1] else {
            return XCTFail("Expected a table then an unordered list, got \(kinds)")
        }
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

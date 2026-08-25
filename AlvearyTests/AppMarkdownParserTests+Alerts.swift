import Foundation
import XCTest

@testable import Alveary

/// GitHub alerts: which blockquotes carry a `[!KIND]` marker, and what the renderers get once the
/// marker is stripped off the body.
extension AppMarkdownParserTests {
    func testEveryAlertKindParsesFromItsMarker() throws {
        for kind in AppMarkdownAlertKind.allCases {
            let alert = try XCTUnwrap(
                alert(in: "> [!\(kind.rawValue.uppercased())]\n> Body text."),
                "Expected \(kind.rawValue) to parse."
            )
            XCTAssertEqual(alert.kind, kind)
        }
    }

    func testAlertMarkerIsStrippedFromTheBody() throws {
        let alert = try XCTUnwrap(alert(in: "> [!WARNING]\n> Do not merge yet."))

        XCTAssertEqual(String(alert.contentWithoutMarker.characters), "Do not merge yet.")
        XCTAssertTrue(alert.hasBody)
    }

    func testAlertMarkerIsCaseInsensitive() throws {
        let alert = try XCTUnwrap(alert(in: "> [!Caution]\n> Careful."))

        XCTAssertEqual(alert.kind, .caution)
    }

    func testMarkerlessQuoteIsNotAnAlert() {
        XCTAssertNil(alert(in: "> Just a quote."))
    }

    func testUnknownMarkerKindIsNotAnAlert() {
        XCTAssertNil(alert(in: "> [!DANGER]\n> Careful."))
    }

    func testMarkerNeedingASeparatorIsNotAnAlert() {
        // `[!NOTE]x` is body text on GitHub too — the marker owns its whole line.
        XCTAssertNil(alert(in: "> [!NOTE]x\n> Body."))
    }

    func testMarkerAfterTheFirstLineIsNotAnAlert() {
        XCTAssertNil(alert(in: "> Intro line.\n> [!NOTE]\n> Body."))
    }

    func testBodylessAlertReportsNoBody() throws {
        let alert = try XCTUnwrap(alert(in: "> [!TIP]"))

        XCTAssertEqual(alert.kind, .tip)
        XCTAssertFalse(alert.hasBody)
    }

    /// A pull request body reaches the renderers through `PullRequestMarkdown.sanitized(_:)`, which
    /// makes every in-paragraph newline a hard break — so the marker's separator is a real `\n`
    /// rather than the space Foundation folds a soft break into.
    func testAlertParsesWithHardBreaksApplied() throws {
        let sanitized = PullRequestMarkdown.sanitized("> [!CAUTION]\n> Do not merge yet.")
        let alert = try XCTUnwrap(alert(in: sanitized))

        XCTAssertEqual(alert.kind, .caution)
        XCTAssertEqual(String(alert.contentWithoutMarker.characters), "Do not merge yet.")
    }

    func testAlertKeepsBodyBlockStructure() throws {
        let markdown = "> [!NOTE]\n> Lead paragraph.\n>\n> - First\n> - Second"
        let quote = try XCTUnwrap(quote(in: markdown))
        let alert = try XCTUnwrap(AppMarkdownAlert(content: quote.content))
        let blocks = alert.contentWithoutMarker.appMarkdownBlockRuns(parent: quote.intent)

        // Stripping a prefix must not flatten the quote's children into one run: the renderers
        // recurse on `contentWithoutMarker` under the quote's own intent.
        XCTAssertGreaterThan(blocks.count, 1)
    }

    /// The alert as `AppKitMarkdownBlockRenderer.quoteView` and `measureQuote` see it: built from a
    /// top-level blockquote run's content, marker and all.
    private func alert(in markdown: String) -> AppMarkdownAlert? {
        quote(in: markdown).flatMap { AppMarkdownAlert(content: $0.content) }
    }

    private func quote(in markdown: String) -> (intent: PresentationIntent.IntentType?, content: AttributedString)? {
        let document = AppMarkdownParser().documentPreservingSource(for: markdown)
        for run in document.content.appMarkdownBlockRuns(parent: nil) {
            guard case .blockQuote = run.intent?.kind else {
                continue
            }
            return (run.intent, AttributedString(document.content[run.range]))
        }
        return nil
    }
}

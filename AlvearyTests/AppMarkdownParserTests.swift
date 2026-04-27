import SwiftUI
import XCTest

@testable import Alveary

final class AppMarkdownParserTests: XCTestCase {
    func testParsesMultiLineFencedCodeBlockWithLanguageHint() throws {
        let parser = AppMarkdownParser()
        let attributed = try parser.attributedString(
            for: """
            ```swift
            let value = 1
            print(value)
            ```
            """
        )

        XCTAssertEqual(String(attributed.characters), "let value = 1\nprint(value)\n")

        let codeBlockRuns = attributed.runs.filter { run in
            run.presentationIntent?.components.contains { component in
                if case .codeBlock(let languageHint) = component.kind {
                    return languageHint == "swift"
                }
                return false
            } == true
        }
        XCTAssertFalse(codeBlockRuns.isEmpty)
    }

    func testParsesUnknownFencedCodeBlockWithoutDroppingContent() throws {
        let parser = AppMarkdownParser()
        let attributed = try parser.attributedString(
            for: """
            ```madeup
              keep indentation
            and content
            ```
            """
        )

        XCTAssertEqual(String(attributed.characters), "  keep indentation\nand content\n")
        XCTAssertTrue(attributed.runs.contains { run in
            run.presentationIntent?.components.contains { component in
                if case .codeBlock(let languageHint) = component.kind {
                    return languageHint == "madeup"
                }
                return false
            } == true
        })
    }

    func testParsesMarkdownTablePresentationIntent() throws {
        let parser = AppMarkdownParser()
        let attributed = try parser.attributedString(
            for: """
            | Name | Count |
            | :--- | ----: |
            | A | 1 |
            """
        )

        let tableComponents = attributed.runs.flatMap { run in
            run.presentationIntent?.components ?? []
        }.filter { component in
            if case .table = component.kind {
                return true
            }
            return false
        }

        XCTAssertFalse(tableComponents.isEmpty)
        XCTAssertEqual(String(attributed.characters), "NameCountA1")
    }

    func testImageMarkdownFallsBackToAltText() throws {
        let parser = AppMarkdownParser(baseURL: URL(string: "https://example.com/docs/"))
        let attributed = try parser.attributedString(for: "![Architecture diagram](images/diagram.png)")

        XCTAssertEqual(String(attributed.characters), "Architecture diagram")
    }

    func testImageMarkdownWithoutAltTextFallsBackToDestinationText() throws {
        let parser = AppMarkdownParser(baseURL: URL(string: "https://example.com/docs/"))
        let attributed = try parser.attributedString(for: "![](images/diagram.png)")

        XCTAssertEqual(String(attributed.characters), "images/diagram.png")
    }

    func testImageMarkdownInsideInlineCodeIsPreservedAsCodeText() throws {
        let parser = AppMarkdownParser(baseURL: URL(string: "https://example.com/docs/"))
        let attributed = try parser.attributedString(for: "`![](images/diagram.png)`")

        XCTAssertEqual(String(attributed.characters), "![](images/diagram.png)")
        XCTAssertTrue(attributed.runs.allSatisfy { $0.inlinePresentationIntent?.contains(.code) == true })
    }

    func testHTMLSubsetMapsToAttributedMarkdownStyles() throws {
        let parser = AppMarkdownParser()
        let attributed = try parser.attributedString(
            for: #"<b>bold</b> <strong>strong</strong> <i>italic</i> <em>em</em> <u>under</u> <a href="https://example.com">site</a>"#
        )

        XCTAssertEqual(String(attributed.characters), "bold strong italic em under site")
        XCTAssertTrue(run(for: "bold", in: attributed)?.inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
        XCTAssertTrue(run(for: "strong", in: attributed)?.inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
        XCTAssertTrue(run(for: "italic", in: attributed)?.inlinePresentationIntent?.contains(.emphasized) == true)
        XCTAssertTrue(run(for: "em", in: attributed)?.inlinePresentationIntent?.contains(.emphasized) == true)
        XCTAssertNotNil(run(for: "under", in: attributed)?.underlineStyle)
        XCTAssertEqual(run(for: "site", in: attributed)?.link, URL(string: "https://example.com"))
    }

    func testHTMLParagraphTagsDoNotRenderAsLiteralTags() throws {
        let parser = AppMarkdownParser()
        let attributed = try parser.attributedString(for: "<p>First</p><p>Second</p>")
        let text = String(attributed.characters)

        XCTAssertTrue(text.contains("First"))
        XCTAssertTrue(text.contains("Second"))
        XCTAssertFalse(text.contains("<p>"))
    }

    func testHTMLSubsetInsideInlineCodeIsPreservedAsCodeText() throws {
        let parser = AppMarkdownParser()
        let attributed = try parser.attributedString(for: "`<b>literal</b>`")

        XCTAssertEqual(String(attributed.characters), "<b>literal</b>")
        XCTAssertTrue(attributed.runs.allSatisfy { $0.inlinePresentationIntent?.contains(.code) == true })
    }

    func testThematicBreakParsesAsHorizontalRule() throws {
        let parser = AppMarkdownParser()
        let attributed = try parser.attributedString(for: "---")

        XCTAssertTrue(attributed.runs.contains { run in
            run.presentationIntent?.components.contains { component in
                if case .thematicBreak = component.kind {
                    return true
                }
                return false
            } == true
        })
    }

    func testDocumentCacheSeparatesTaskStateScopeFromParsedContent() {
        let markdown = "- [ ] Review"
        let first = cachedDocument(for: markdown, taskStateScope: "message-1")
        let second = cachedDocument(for: markdown, taskStateScope: "message-2")

        XCTAssertEqual(first.content, second.content)
        XCTAssertNotEqual(first.taskStateNamespace, second.taskStateNamespace)
    }

    private func run(
        for text: String,
        in attributed: AttributedString
    ) -> AttributedString.Runs.Run? {
        attributed.runs.first { run in
            String(attributed[run.range].characters) == text
        }
    }

    private func cachedDocument(
        for markdown: String,
        taskStateScope: String
    ) -> AppMarkdownDocument {
        AppMarkdownDocumentCache.document(
            markdown: markdown,
            context: AppMarkdownDocumentCacheContext(
                baseURL: nil,
                inlineCodeStyle: .standard,
                hasComposerChipProvider: false,
                taskStateScope: taskStateScope
            )
        ) {
            AppMarkdownParser().documentPreservingSource(for: markdown)
        }
    }
}

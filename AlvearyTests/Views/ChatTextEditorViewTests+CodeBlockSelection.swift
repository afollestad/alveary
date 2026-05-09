import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatTextEditorViewTests {
    func testHiddenCodeBlockDelimiterRectsCoverFullSelectionRows() throws {
        let editor = makeEditor()
        let text = "```\nTest\n```"

        editor.configure(ChatTextEditorConfiguration(
            text: text,
            selectedRange: NSRange(location: 0, length: (text as NSString).length),
            codeBlockRanges: AppMarkdownCodeBlockParser.blockRanges,
            inlineCodeBackgroundRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeDelimiterRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineDelimiterRanges }
        ))
        editor.layoutSubtreeIfNeeded()
        flushMainQueue()

        let textView = editor.textViewForTesting
        let delimiterRects = textView.hiddenCodeBlockDelimiterRects()

        XCTAssertEqual(delimiterRects.count, 2)
        XCTAssertTrue(delimiterRects.allSatisfy { rect in
            abs(rect.minX - textView.bounds.minX) <= 0.5 &&
                abs(rect.width - textView.bounds.width) <= 0.5
        })
    }
}

import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatTextEditorViewTests {
    func testTypingOpeningFenceBeforeExistingLineMovesLineIntoCodeBlock() {
        let editor = makeEditor()
        var currentText = "let value = 1"
        var currentSelection: NSRange? = NSRange(location: 0, length: 0)

        editor.configure(ChatTextEditorConfiguration(
            text: currentText,
            selectedRange: currentSelection,
            codeBlockRanges: AppMarkdownCodeBlockParser.blockRanges,
            inlineCodeBackgroundRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeDelimiterRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineDelimiterRanges },
            onTextChange: { currentText = $0 },
            onSelectionChange: { currentSelection = $0 }
        ))
        editor.layoutSubtreeIfNeeded()
        flushMainQueue()

        let textView = editor.textViewForTesting
        textView.perform(NSSelectorFromString("insertText:"), with: "```")
        editor.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(currentText, "```\nlet value = 1")
        XCTAssertEqual(currentSelection, NSRange(location: ("```\n" as NSString).length, length: 0))
        XCTAssertNotEqual(
            textView.textStorage?.attribute(.foregroundColor, at: ("```\n" as NSString).length, effectiveRange: nil) as? NSColor,
            .clear
        )
    }

    func testTypingAttributedOpeningFenceBeforeExistingLineMovesLineIntoCodeBlock() {
        let editor = makeEditor()
        var currentText = "let value = 1"
        var currentSelection: NSRange? = NSRange(location: 0, length: 0)

        editor.configure(ChatTextEditorConfiguration(
            text: currentText,
            selectedRange: currentSelection,
            codeBlockRanges: AppMarkdownCodeBlockParser.blockRanges,
            inlineCodeBackgroundRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeDelimiterRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineDelimiterRanges },
            onTextChange: { currentText = $0 },
            onSelectionChange: { currentSelection = $0 }
        ))
        editor.layoutSubtreeIfNeeded()
        flushMainQueue()

        let textView = editor.textViewForTesting
        for _ in 0..<3 {
            textView.insertText(NSAttributedString(string: "`"), replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        editor.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(currentText, "```\nlet value = 1")
        XCTAssertEqual(currentSelection, NSRange(location: ("```\n" as NSString).length, length: 0))
        XCTAssertEqual(AppMarkdownCodeBlockParser.codeRanges(in: currentText).blockContentRanges.first, NSRange(location: 4, length: 13))
    }
}

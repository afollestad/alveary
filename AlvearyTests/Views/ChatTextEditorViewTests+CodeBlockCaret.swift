import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatTextEditorViewTests {
    func testEmptyFencedCodeBlockInsertionPointCanEraseAdjustedCaretRect() throws {
        let editor = makeEditor()
        let text = "```\n"

        editor.configure(ChatTextEditorConfiguration(
            text: text,
            selectedRange: NSRange(location: (text as NSString).length, length: 0),
            codeBlockRanges: AppMarkdownCodeBlockParser.blockRanges,
            inlineCodeBackgroundRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeDelimiterRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineDelimiterRanges }
        ))
        editor.layoutSubtreeIfNeeded()
        flushMainQueue()

        let textView = editor.textViewForTesting
        let blockContentRange = try XCTUnwrap(AppMarkdownCodeBlockParser.codeRanges(in: text).blockContentRanges.first)
        let backgroundRect = try XCTUnwrap(textView.codeBlockBackgroundRects(for: blockContentRange).first)
        let proposedRect = NSRect(x: backgroundRect.minX, y: backgroundRect.midY, width: 2, height: 2)

        try withBitmapGraphicsContext(size: textView.bounds.size) {
            XCTAssertTrue(textView.eraseEmptyCodeBlockInsertionPoint(from: proposedRect))
        }
    }

    func testEmptyFencedCodeBlockInsertionPointDoesNotEraseWithoutGraphicsContext() throws {
        let editor = makeEditor()
        let text = "```\n"

        editor.configure(ChatTextEditorConfiguration(
            text: text,
            selectedRange: NSRange(location: (text as NSString).length, length: 0),
            codeBlockRanges: AppMarkdownCodeBlockParser.blockRanges,
            inlineCodeBackgroundRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeDelimiterRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineDelimiterRanges }
        ))
        editor.layoutSubtreeIfNeeded()
        flushMainQueue()

        let textView = editor.textViewForTesting
        let blockContentRange = try XCTUnwrap(AppMarkdownCodeBlockParser.codeRanges(in: text).blockContentRanges.first)
        let backgroundRect = try XCTUnwrap(textView.codeBlockBackgroundRects(for: blockContentRange).first)
        let proposedRect = NSRect(x: backgroundRect.minX, y: backgroundRect.midY, width: 2, height: 2)

        XCTAssertFalse(textView.eraseEmptyCodeBlockInsertionPoint(from: proposedRect))
    }

    func testNonEmptyFencedCodeBlockInsertionPointUsesAppKitErasePath() {
        let editor = makeEditor()
        let text = "```\nTest"

        editor.configure(ChatTextEditorConfiguration(
            text: text,
            selectedRange: NSRange(location: (text as NSString).length, length: 0),
            codeBlockRanges: AppMarkdownCodeBlockParser.blockRanges,
            inlineCodeBackgroundRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeDelimiterRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineDelimiterRanges }
        ))
        editor.layoutSubtreeIfNeeded()
        flushMainQueue()

        XCTAssertFalse(editor.textViewForTesting.eraseEmptyCodeBlockInsertionPoint(from: NSRect(x: 0, y: 0, width: 2, height: 2)))
    }

    private func withBitmapGraphicsContext(
        size: NSSize,
        _ body: () throws -> Void
    ) throws {
        let width = max(Int(ceil(size.width)), 1)
        let height = max(Int(ceil(size.height)), 1)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [.alphaFirst],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        let previousContext = NSGraphicsContext.current
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.current = previousContext }
        try body()
    }
}

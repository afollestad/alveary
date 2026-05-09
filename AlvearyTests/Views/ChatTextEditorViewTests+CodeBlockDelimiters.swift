import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatTextEditorViewTests {
    func testClosingFenceLineReservesBottomPaddingBeforeTrailingBlankLine() throws {
        let editor = makeEditor()
        let text = "Test\n```\nlet value = 1\n```\n"

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
        let blockRange = try XCTUnwrap(AppMarkdownCodeBlockParser.blockCodeRanges(in: text).first)
        let closingDelimiter = try XCTUnwrap(blockRange.delimiterRanges.dropFirst().first)
        let paragraphStyle = try XCTUnwrap(
            textView.textStorage?.attribute(.paragraphStyle, at: closingDelimiter.location, effectiveRange: nil) as? NSParagraphStyle
        )

        XCTAssertEqual(
            paragraphStyle.maximumLineHeight,
            AppTextEditorCodeBlockStyling.codeBlockVerticalPadding + AppTextEditorCodeBlockStyling.codeBlockOuterGap,
            accuracy: 0.5
        )
        XCTAssertEqual(textView.selectedRange(), NSRange(location: (text as NSString).length, length: 0))
        let typingParagraphStyle = textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(typingParagraphStyle?.headIndent, 0)
    }

    func testTrailingClosedCodeBlockCaretDrawsOnOutsideTextLine() throws {
        let editor = makeEditor()
        let text = "Test\n```\nlet value = 1\n```\n"

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
        let blockRange = try XCTUnwrap(AppMarkdownCodeBlockParser.blockCodeRanges(in: text).first)
        let backgroundRect = try XCTUnwrap(textView.codeBlockBackgroundRects(for: blockRange.contentRange).first)
        let proposedRect = NSRect(x: backgroundRect.minX, y: backgroundRect.midY, width: 2, height: 2)
        let adjustedRect = try XCTUnwrap(textView.codeBlockInsertionPointRect(from: proposedRect))

        XCTAssertEqual(adjustedRect.minX, textView.textContainerInset.width + (textView.textContainer?.lineFragmentPadding ?? 0), accuracy: 0.5)
        XCTAssertEqual(adjustedRect.minY - backgroundRect.maxY, AppTextEditorCodeBlockStyling.codeBlockOuterGap, accuracy: 0.5)
        let minimumBackgroundHeight = ceil((textView.layoutManager?.defaultLineHeight(for: textView.baseTextFont) ?? 0) +
            (AppTextEditorCodeBlockStyling.codeBlockVerticalPadding * 2))
        XCTAssertGreaterThanOrEqual(backgroundRect.height, minimumBackgroundHeight - 1)
        try withBitmapGraphicsContext(size: textView.bounds.size) {
            XCTAssertTrue(textView.eraseEmptyCodeBlockInsertionPoint(from: proposedRect))
        }
    }

    func testTrailingClosedCodeBlockBackgroundStopsBeforeOutsideLine() throws {
        let editor = makeEditor()
        let text = "Test\n```\nlet value = 1\n```\nHi"

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
        let blockRange = try XCTUnwrap(AppMarkdownCodeBlockParser.blockCodeRanges(in: text).first)
        let backgroundRect = try XCTUnwrap(textView.codeBlockBackgroundRects(for: blockRange.contentRange).first)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let outsideGlyphIndex = layoutManager.glyphIndexForCharacter(at: (text as NSString).range(of: "Hi").location)
        let outsideLineRect = layoutManager.lineFragmentRect(forGlyphAt: outsideGlyphIndex, effectiveRange: nil)
        let outsideLineMinY = outsideLineRect.minY + textView.textContainerOrigin.y

        XCTAssertEqual(outsideLineMinY - backgroundRect.maxY, AppTextEditorCodeBlockStyling.codeBlockOuterGap, accuracy: 0.5)
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

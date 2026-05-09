import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatTextEditorViewTests {
    func testProgrammaticHeightPrimingShrinksAfterShorterDraftRestore() {
        let tallHeight = ChatTextEditor.primedMeasuredHeight(
            for: "One\nTwo\nThree\nFour\nFive",
            minHeight: 68,
            verticalPadding: 10
        )
        let shortHeight = ChatTextEditor.primedMeasuredHeight(
            for: "f\nf",
            minHeight: 68,
            verticalPadding: 10
        )

        XCTAssertEqual(shortHeight, 68)
        XCTAssertLessThan(shortHeight, tallHeight)
    }

    func testProgrammaticHeightPrimingUsesNativeLineHeight() {
        let height = ChatTextEditor.primedMeasuredHeight(
            for: "d\nd\nd\nd\nd",
            minHeight: 68,
            verticalPadding: 10
        )
        let expectedHeight = (ChatTextEditor.primedLineHeight * 5) + 20

        XCTAssertEqual(height, expectedHeight, accuracy: 0.5)
        XCTAssertLessThan(height, 120)
    }

    func testProgrammaticHeightPrimingIncludesCodeBlockChrome() {
        let height = ChatTextEditor.primedMeasuredHeight(
            for: "Test\n```\nTest",
            minHeight: 68,
            verticalPadding: 10
        )
        let expectedHeight = (ChatTextEditor.primedLineHeight * 2) +
            (AppTextEditorCodeBlockStyling.codeBlockVerticalPadding * 2) +
            (AppTextEditorCodeBlockStyling.codeBlockOuterGap * 2) +
            (10 * 2)

        XCTAssertEqual(height, expectedHeight, accuracy: 0.5)
        XCTAssertGreaterThan(height, 68)
    }

    func testProgrammaticHeightPrimingIgnoresHiddenCodeBlockFenceLines() {
        let height = ChatTextEditor.primedMeasuredHeight(
            for: "```\nTest\nTest\nTest\nTest\nTest\n```",
            minHeight: 68,
            verticalPadding: 10
        )
        let expectedHeight = (ChatTextEditor.primedLineHeight * 5) +
            (AppTextEditorCodeBlockStyling.codeBlockVerticalPadding * 2) +
            (AppTextEditorCodeBlockStyling.codeBlockOuterGap * 2) +
            (10 * 2)

        XCTAssertEqual(height, expectedHeight, accuracy: 0.5)
        XCTAssertLessThan(
            height,
            (ChatTextEditor.primedLineHeight * 7) + (10 * 2)
        )
    }

    func testProgrammaticHeightPrimingIncludesTrailingOutsideLineAfterClosedCodeBlock() {
        let height = ChatTextEditor.primedMeasuredHeight(
            for: "Test\n```\nTest\n```\n",
            minHeight: 68,
            verticalPadding: 10
        )
        let expectedHeight = (ChatTextEditor.primedLineHeight * 3) +
            (AppTextEditorCodeBlockStyling.codeBlockVerticalPadding * 2) +
            (AppTextEditorCodeBlockStyling.codeBlockOuterGap * 2) +
            (10 * 2)

        XCTAssertEqual(height, expectedHeight, accuracy: 0.5)
    }

    func testFencedCodeBlockMeasurementIncludesDrawnChromeHeight() throws {
        let editor = makeEditor()
        let text = "Test\n```\nfff"
        var measuredHeight: CGFloat = 0

        editor.configure(ChatTextEditorConfiguration(
            text: text,
            codeBlockRanges: AppMarkdownCodeBlockParser.blockRanges,
            inlineCodeBackgroundRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeDelimiterRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineDelimiterRanges },
            onMeasuredHeightChange: { measuredHeight = $0 }
        ))
        editor.layoutSubtreeIfNeeded()
        editor.measureAndRefreshForCurrentLayout()
        flushMainQueue()

        let textView = editor.textViewForTesting
        let preferredHeight = try XCTUnwrap(textView.codeBlockPreferredContentHeight())
        let visualHeight = try XCTUnwrap(textView.codeBlockVisualContentHeight())

        XCTAssertGreaterThan(preferredHeight, visualHeight)
        XCTAssertEqual(measuredHeight, preferredHeight, accuracy: 0.5)
    }

    func testShortFencedCodeBlockMeasurementUsesSymmetricBottomGap() throws {
        let editor = makeEditor()
        let text = "```\nfff"
        var measuredHeight: CGFloat = 0

        editor.configure(ChatTextEditorConfiguration(
            text: text,
            codeBlockRanges: AppMarkdownCodeBlockParser.blockRanges,
            inlineCodeBackgroundRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeDelimiterRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineDelimiterRanges },
            onMeasuredHeightChange: { measuredHeight = $0 }
        ))
        editor.layoutSubtreeIfNeeded()
        editor.measureAndRefreshForCurrentLayout()
        flushMainQueue()

        let textView = editor.textViewForTesting
        let visualHeight = try XCTUnwrap(textView.codeBlockVisualContentHeight())
        XCTAssertEqual(measuredHeight, try XCTUnwrap(textView.codeBlockPreferredContentHeight()), accuracy: 0.5)
        XCTAssertEqual(
            measuredHeight - visualHeight,
            AppTextEditorCodeBlockStyling.codeBlockComposerBreathingRoom,
            accuracy: 0.5
        )
    }

    func testClosedCodeBlockMeasurementIncludesTrailingOutsideLine() throws {
        let editor = makeEditor()
        let text = "Test\n```\nTest\n```\n"
        var measuredHeight: CGFloat = 0

        editor.configure(ChatTextEditorConfiguration(
            text: text,
            selectedRange: NSRange(location: (text as NSString).length, length: 0),
            codeBlockRanges: AppMarkdownCodeBlockParser.blockRanges,
            inlineCodeBackgroundRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeDelimiterRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineDelimiterRanges },
            onMeasuredHeightChange: { measuredHeight = $0 }
        ))
        editor.layoutSubtreeIfNeeded()
        editor.measureAndRefreshForCurrentLayout()
        flushMainQueue()

        let textView = editor.textViewForTesting
        let blockRange = try XCTUnwrap(AppMarkdownCodeBlockParser.blockCodeRanges(in: text).first)
        let backgroundRect = try XCTUnwrap(textView.codeBlockBackgroundRects(for: blockRange.contentRange).first)
        let lineHeight = try XCTUnwrap(textView.layoutManager?.defaultLineHeight(for: textView.baseTextFont))
        let expectedMinimumHeight = backgroundRect.maxY +
            AppTextEditorCodeBlockStyling.codeBlockOuterGap +
            ceil(lineHeight) +
            textView.textContainerInset.height

        XCTAssertEqual(measuredHeight, expectedMinimumHeight, accuracy: 0.5)
    }
}

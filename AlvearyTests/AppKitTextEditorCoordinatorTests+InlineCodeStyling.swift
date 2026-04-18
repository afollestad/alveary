import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension AppKitTextEditorCoordinatorTests {
    func testMarkdownCodeRangesSeparateInlineContentFromDelimiters() {
        let ranges = AppMarkdownCodeBlockParser.codeRanges(in: "Test `code block`")

        XCTAssertEqual(ranges.blockRanges, [])
        XCTAssertEqual(ranges.inlineFullRanges, [NSRange(location: 5, length: 12)])
        XCTAssertEqual(ranges.inlineContentRanges, [NSRange(location: 6, length: 10)])
        XCTAssertEqual(ranges.inlineDelimiterRanges, [NSRange(location: 5, length: 1), NSRange(location: 16, length: 1)])
    }

    func testMarkdownCodeRangesIgnoreInlineDelimitersInsideFencedBlocks() {
        let markdown = "```swift\nlet name = `debug`\n```"
        let ranges = AppMarkdownCodeBlockParser.codeRanges(in: markdown)

        XCTAssertEqual(ranges.blockRanges, [NSRange(location: 0, length: (markdown as NSString).length)])
        XCTAssertTrue(ranges.inlineFullRanges.isEmpty)
        XCTAssertTrue(ranges.inlineContentRanges.isEmpty)
        XCTAssertTrue(ranges.inlineDelimiterRanges.isEmpty)
    }

    func testMarkdownCodeRangesIgnoreAdjacentBackticksWithoutContent() {
        let ranges = AppMarkdownCodeBlockParser.codeRanges(in: "Test `` world")

        XCTAssertEqual(ranges.blockRanges, [])
        XCTAssertTrue(ranges.inlineFullRanges.isEmpty)
        XCTAssertTrue(ranges.inlineContentRanges.isEmpty)
        XCTAssertTrue(ranges.inlineDelimiterRanges.isEmpty)
    }

    func testAppMarkdownParserAttachesInlineCodeChipsWithoutAffectingFencedBlocks() throws {
        let parser = AppMarkdownParser(baseURL: nil, inlineCodeStyle: .standard)
        let attributedString = try parser.attributedString(
            for: "Use `git status` here.\n```swift\nlet count = 1\n```"
        )

        let attachedInlineRanges = attributedString.runs.compactMap { run -> Range<AttributedString.Index>? in
            guard run.textual.attachment != nil else {
                return nil
            }
            return run.range
        }

        XCTAssertEqual(attachedInlineRanges.count, 1)
        XCTAssertEqual(String(attributedString[attachedInlineRanges[0]].characters), "git status")
    }

    func testAppMarkdownParserSkipsComposerChipsInsideFencedBlocks() throws {
        let parser = AppMarkdownParser(
            baseURL: nil,
            inlineCodeStyle: .userBubble,
            composerChipProvider: ChatInputFieldTextSupport.composerTextChips(in:)
        )
        let attributedString = try parser.attributedString(
            for: "```\n@Alveary/Views/Input/ChatInputField.swift\n```"
        )

        let attachmentCount = attributedString.runs.filter { $0.textual.attachment != nil }.count
        XCTAssertEqual(attachmentCount, 0)
    }

    func testAppMarkdownParserSkipsComposerChipsInsideMarkdownLinks() throws {
        let parser = AppMarkdownParser(
            baseURL: nil,
            inlineCodeStyle: .userBubble,
            composerChipProvider: ChatInputFieldTextSupport.composerTextChips(in:)
        )
        let attributedString = try parser.attributedString(
            for: "See [@Alveary/Views/Input/ChatInputField.swift](https://example.com) please."
        )

        let attachmentCount = attributedString.runs.filter { $0.textual.attachment != nil }.count
        XCTAssertEqual(attachmentCount, 0)
    }

    func testAppMarkdownParserAttachesComposerChipsInPlainProse() throws {
        let parser = AppMarkdownParser(
            baseURL: nil,
            inlineCodeStyle: .userBubble,
            composerChipProvider: ChatInputFieldTextSupport.composerTextChips(in:)
        )
        let attributedString = try parser.attributedString(
            for: "/review-github-pr look at @Alveary/Views/Input/ChatInputField.swift next"
        )

        let attachmentTexts = attributedString.runs.compactMap { run -> String? in
            guard run.textual.attachment != nil else {
                return nil
            }
            return String(attributedString[run.range].characters)
        }

        XCTAssertEqual(attachmentTexts, ["/review-github-pr", "@Alveary/Views/Input/ChatInputField.swift"])
    }

    func testInlineCodeDelimiterStylingCollapsesDelimiterLayoutWidth() {
        let textView = AppKitTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 120))
        textView.font = .preferredFont(forTextStyle: .body)
        textView.baseTextFont = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        textView.string = "Test `hello` world"

        guard let textStorage = textView.textStorage,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return XCTFail("Expected TextKit stack")
        }

        let ranges = AppMarkdownCodeBlockParser.codeRanges(in: textView.string)
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let baseFont = textView.baseTextFont

        textStorage.beginEditing()
        AppTextEditorCodeBlockStyling.apply(
            to: textStorage,
            context: .init(
                fullRange: fullRange,
                highlightRanges: [],
                blockRanges: ranges.blockRanges,
                inlineRanges: ranges.inlineContentRanges,
                inlineDelimiterRanges: ranges.inlineDelimiterRanges,
                baseFont: baseFont,
                baseColor: .labelColor,
                colorScheme: .dark
            )
        )
        textStorage.endEditing()

        func enclosingRect(for range: NSRange) -> NSRect? {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect: NSRect?
            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: textContainer
            ) { enclosingRect, _ in
                rect = rect.map { $0.union(enclosingRect) } ?? enclosingRect
            }
            return rect
        }

        layoutManager.ensureLayout(for: textContainer)
        guard let fullRect = enclosingRect(for: ranges.inlineFullRanges[0]),
              let contentRect = enclosingRect(for: ranges.inlineContentRanges[0]) else {
            return XCTFail("Expected inline code rects")
        }

        XCTAssertGreaterThan(fullRect.width - contentRect.width, 4)
        XCTAssertLessThan(fullRect.width - contentRect.width, 8)
    }

    func testCompactFileMentionStylingHidesPathPrefixButKeepsFilenameVisible() {
        let textView = AppKitTextView(frame: NSRect(x: 0, y: 0, width: 760, height: 120))
        textView.font = .preferredFont(forTextStyle: .body)
        textView.baseTextFont = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 760, height: CGFloat.greatestFiniteMagnitude)
        textView.string = "Inspect @Alveary/Views/Input/ChatInputField.swift next"

        let chip = AppTextEditorChip(
            range: NSRange(location: 8, length: 41),
            displayText: "@ChatInputField.swift",
            style: .fileMention
        )

        guard let textStorage = textView.textStorage else {
            return XCTFail("Expected text storage")
        }

        AppTextEditorCodeBlockStyling.applyTextChips(
            to: textStorage,
            chips: [chip],
            fullRange: NSRange(location: 0, length: textStorage.length),
            compactDisplayResolver: { _ in true }
        )

        let hiddenPrefixColor = textStorage.attribute(.foregroundColor, at: 9, effectiveRange: nil) as? NSColor
        let hiddenPrefixFont = textStorage.attribute(.font, at: 9, effectiveRange: nil) as? NSFont
        let visibleSuffixColor = textStorage.attribute(.foregroundColor, at: 30, effectiveRange: nil) as? NSColor

        XCTAssertEqual(hiddenPrefixColor, .clear)
        XCTAssertLessThan(hiddenPrefixFont?.pointSize ?? .greatestFiniteMagnitude, 1)
        XCTAssertEqual(visibleSuffixColor, AppMarkdownCodeBlockPalette.inlineForegroundNSColor)
    }

    func testTextChipUsesInlineCodeFontStyling() {
        let textView = AppKitTextView(frame: NSRect(x: 0, y: 0, width: 760, height: 120))
        textView.font = .preferredFont(forTextStyle: .body)
        textView.baseTextFont = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 760, height: CGFloat.greatestFiniteMagnitude)
        textView.string = "/android-emulator test"

        let chip = AppTextEditorChip(
            range: NSRange(location: 0, length: 17),
            displayText: "/android-emulator",
            style: .slashCommand
        )

        guard let textStorage = textView.textStorage else {
            return XCTFail("Expected text storage")
        }

        AppTextEditorCodeBlockStyling.applyTextChips(
            to: textStorage,
            chips: [chip],
            fullRange: NSRange(location: 0, length: textStorage.length),
            compactDisplayResolver: { _ in false }
        )

        let chipFont = textStorage.attribute(.font, at: chip.range.location, effectiveRange: nil) as? NSFont
        let inlineCodeFont = NSFont.monospacedSystemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize * 0.94,
            weight: .regular
        )

        XCTAssertEqual(chipFont?.fontName, inlineCodeFont.fontName)
        XCTAssertEqual(chipFont?.pointSize, inlineCodeFont.pointSize)
    }

    func testSlashCommandChipLeavesGapBeforeFollowingWord() {
        let textView = AppKitTextView(frame: NSRect(x: 0, y: 0, width: 760, height: 120))
        textView.font = .preferredFont(forTextStyle: .body)
        textView.baseTextFont = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 760, height: CGFloat.greatestFiniteMagnitude)
        textView.string = "/android-emulator test"

        let chip = AppTextEditorChip(
            range: NSRange(location: 0, length: 17),
            displayText: "/android-emulator",
            style: .slashCommand
        )

        guard let chipRect = textView.textChipRects(for: chip.range).first,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return XCTFail("Expected chip rect")
        }

        layoutManager.ensureLayout(for: textContainer)
        let nextWordGlyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: 18, length: 1), actualCharacterRange: nil)
        let nextWordRect = layoutManager.boundingRect(forGlyphRange: nextWordGlyphRange, in: textContainer)

        XCTAssertLessThan(chipRect.maxX, textView.textContainerOrigin.x + nextWordRect.minX)
    }

    func testFileMentionChipLeavesGapBeforeFollowingWord() {
        let textView = AppKitTextView(frame: NSRect(x: 0, y: 0, width: 760, height: 120))
        textView.font = .preferredFont(forTextStyle: .body)
        textView.baseTextFont = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 760, height: CGFloat.greatestFiniteMagnitude)
        textView.string = "Test @pipeline.yaml file mention"

        let chip = AppTextEditorChip(
            range: NSRange(location: 5, length: 14),
            displayText: "@pipeline.yaml",
            style: .fileMention
        )

        guard let chipRect = textView.textChipRects(for: chip.range).first,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return XCTFail("Expected chip rect")
        }

        layoutManager.ensureLayout(for: textContainer)
        let previousWordGlyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: 0, length: 1), actualCharacterRange: nil)
        let previousWordRect = layoutManager.boundingRect(forGlyphRange: previousWordGlyphRange, in: textContainer)
        let nextWordGlyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: 20, length: 1), actualCharacterRange: nil)
        let nextWordRect = layoutManager.boundingRect(forGlyphRange: nextWordGlyphRange, in: textContainer)

        XCTAssertGreaterThan(chipRect.minX, textView.textContainerOrigin.x + previousWordRect.maxX)
        XCTAssertLessThan(chipRect.maxX, textView.textContainerOrigin.x + nextWordRect.minX)
    }

    func testApplyConfigurationUsesStableBaseFontForPlainText() {
        var text = "My name is `Aidan`."
        var measuredHeight: CGFloat = 0

        let parent = AppKitTextEditorView(
            text: Binding(get: { text }, set: { text = $0 }),
            measuredTextHeight: Binding(get: { measuredHeight }, set: { measuredHeight = $0 }),
            placeholder: nil,
            horizontalPadding: 10,
            verticalPadding: 10,
            isDisabled: false,
            focus: nil,
            textHighlightRanges: nil,
            codeBlockRanges: AppMarkdownCodeBlockParser.blockRanges,
            inlineCodeBackgroundRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeDelimiterRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineDelimiterRanges },
            inlineHint: nil,
            keyPressKeys: [],
            onKeyPress: nil
        )

        let coordinator = AppKitTextEditorCoordinator(parent: parent)
        let textView = AppKitTextView(frame: .zero)
        textView.baseTextFont = .preferredFont(forTextStyle: .body)
        textView.font = .monospacedSystemFont(ofSize: textView.baseTextFont.pointSize, weight: .regular)
        textView.string = text

        let scrollView = AppKitTextEditorScrollView(frame: .zero)
        scrollView.documentView = textView
        coordinator.attach(textView: textView, scrollView: scrollView)

        coordinator.applyConfiguration(from: parent)

        guard let textStorage = textView.textStorage else {
            return XCTFail("Expected text storage")
        }

        let plainTextFont = textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let ranges = AppMarkdownCodeBlockParser.codeRanges(in: text)
        let inlineFont = textStorage.attribute(.font, at: ranges.inlineContentRanges[0].location, effectiveRange: nil) as? NSFont

        XCTAssertEqual(plainTextFont?.fontName, textView.baseTextFont.fontName)
        XCTAssertEqual(plainTextFont?.pointSize, textView.baseTextFont.pointSize)
        XCTAssertNotEqual(inlineFont?.fontName, textView.baseTextFont.fontName)
    }
}

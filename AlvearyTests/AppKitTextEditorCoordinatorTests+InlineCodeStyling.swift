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
        XCTAssertEqual(ranges.blockContentRanges, [NSRange(location: 9, length: 19)])
        XCTAssertEqual(ranges.blockDelimiterRanges, [NSRange(location: 0, length: 9), NSRange(location: 28, length: 3)])
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

    // Inline code is rendered as a flat monospaced highlight rather than an attachment
    // view, so chip-lines don't grow taller than non-chip lines in multi-line bubbles.
    // The parsed `AttributedString` marks inline code with `inlinePresentationIntent =
    // .code` and fenced code blocks with a `.codeBlock` component on `presentationIntent`.
    func testAppMarkdownParserMarksInlineCodeWithoutAffectingFencedBlocks() throws {
        let parser = AppMarkdownParser(baseURL: nil)
        let attributedString = try parser.attributedString(
            for: "Use `git status` here.\n```swift\nlet count = 1\n```"
        )

        let inlineCodeRanges = attributedString.runs.compactMap { run -> Range<AttributedString.Index>? in
            guard let intent = run.inlinePresentationIntent, intent.contains(.code) else {
                return nil
            }
            if let presentationIntent = run.presentationIntent,
               presentationIntent.components.contains(where: { component in
                   if case .codeBlock = component.kind { return true }
                   return false
               }) {
                return nil
            }
            return run.range
        }

        XCTAssertEqual(inlineCodeRanges.count, 1)
        XCTAssertEqual(String(attributedString[inlineCodeRanges[0]].characters), "git status")

        let fencedBlockRuns = attributedString.runs.filter { run in
            guard let presentationIntent = run.presentationIntent else { return false }
            return presentationIntent.components.contains { component in
                if case .codeBlock = component.kind { return true }
                return false
            }
        }
        XCTAssertFalse(fencedBlockRuns.isEmpty)
        XCTAssertTrue(inlineCodeRanges.allSatisfy { range in
            attributedString[range].runs.allSatisfy { $0.inlinePresentationIntent?.contains(.code) == true }
        })
    }

    // A file mention inside a fenced code block must not be re-styled as a composer chip —
    // `attachComposerChips` skips ranges whose `presentationIntent` contains `.codeBlock`,
    // so the block's content stays verbatim.
    func testAppMarkdownParserSkipsComposerChipsInsideFencedBlocks() throws {
        let parser = AppMarkdownParser(
            baseURL: nil,
            composerChipProvider: ChatInputFieldTextSupport.composerTextChips(in:)
        )
        let attributedString = try parser.attributedString(
            for: "```\n@Alveary/Views/Input/ChatInputField.swift\n```"
        )

        let flatString = String(attributedString.characters)
        XCTAssertTrue(flatString.contains("@Alveary/Views/Input/ChatInputField.swift"))
        XCTAssertFalse(flatString.contains("@ChatInputField.swift\n"))
    }

    // A file mention used as a markdown link's visible text must stay linked rather than
    // getting rewritten into a composer chip.
    func testAppMarkdownParserSkipsComposerChipsInsideMarkdownLinks() throws {
        let parser = AppMarkdownParser(
            baseURL: nil,
            composerChipProvider: ChatInputFieldTextSupport.composerTextChips(in:)
        )
        let attributedString = try parser.attributedString(
            for: "See [@Alveary/Views/Input/ChatInputField.swift](https://example.com) please."
        )

        let linkedRuns = attributedString.runs.compactMap { run -> String? in
            guard run.link != nil else { return nil }
            return String(attributedString[run.range].characters)
        }
        XCTAssertEqual(linkedRuns, ["@Alveary/Views/Input/ChatInputField.swift"])

        let flatString = String(attributedString.characters)
        XCTAssertTrue(flatString.contains("@Alveary/Views/Input/ChatInputField.swift"))
        XCTAssertFalse(flatString.contains("@ChatInputField.swift "))
    }

    // Plain-prose composer chips (leading `/command`, `@file`) are rewritten to their
    // display text and tagged with `inlinePresentationIntent = .code`, giving them the
    // same flat-highlight treatment as inline code.
    func testAppMarkdownParserRewritesComposerChipsAsInlineCode() throws {
        let parser = AppMarkdownParser(
            baseURL: nil,
            composerChipProvider: ChatInputFieldTextSupport.composerTextChips(in:)
        )
        let attributedString = try parser.attributedString(
            for: "/review-github-pr look at @Alveary/Views/Input/ChatInputField.swift next"
        )

        let chipTexts = attributedString.runs.compactMap { run -> String? in
            guard let intent = run.inlinePresentationIntent, intent.contains(.code) else {
                return nil
            }
            return String(attributedString[run.range].characters)
        }
        XCTAssertEqual(chipTexts, ["/review-github-pr", "@ChatInputField.swift"])

        let flatString = String(attributedString.characters)
        XCTAssertTrue(flatString.contains("@ChatInputField.swift"))
        XCTAssertFalse(flatString.contains("@Alveary/Views/Input/ChatInputField.swift"))

        XCTAssertTrue(chipTexts.allSatisfy { !$0.isEmpty })
    }

    // Regression guard for the fix in `attachComposerChips`: a file mention wrapped in
    // backticks must stay as inline code and keep its full-path text. Without the
    // `inlinePresentationIntent.code` conflict check, the composer chip pipeline would
    // replace the backtick content with the shortened display text.
    func testAppMarkdownParserPreservesInlineCodeAgainstComposerChip() throws {
        let parser = AppMarkdownParser(
            baseURL: nil,
            composerChipProvider: ChatInputFieldTextSupport.composerTextChips(in:)
        )
        let attributedString = try parser.attributedString(
            for: "Inline code wins: `@Alveary/Views/Input/ChatInputField.swift` stays intact."
        )

        let codeRuns = attributedString.runs.compactMap { run -> String? in
            guard let intent = run.inlinePresentationIntent, intent.contains(.code) else {
                return nil
            }
            return String(attributedString[run.range].characters)
        }
        XCTAssertEqual(codeRuns, ["@Alveary/Views/Input/ChatInputField.swift"])

        let flatString = String(attributedString.characters)
        XCTAssertFalse(flatString.contains("@ChatInputField.swift "))
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

    func testFencedCodeBlockUsesContinuousCustomBackgroundInsteadOfTextBackgroundAttribute() throws {
        let markdown = "Please check:\n```swift\nlet values = [1, 2, 3]\nprint(values)\n```"
        let textView = AppKitTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        textView.font = .preferredFont(forTextStyle: .body)
        textView.baseTextFont = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        textView.string = markdown
        textView.updateTextContainerForCurrentBounds()

        guard let textStorage = textView.textStorage,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return XCTFail("Expected TextKit stack")
        }

        let ranges = AppMarkdownCodeBlockParser.codeRanges(in: markdown)
        let codeBlockRange = try XCTUnwrap(ranges.blockRanges.first)

        textStorage.beginEditing()
        AppTextEditorCodeBlockStyling.apply(
            to: textStorage,
            context: .init(
                fullRange: NSRange(location: 0, length: textStorage.length),
                highlightRanges: [],
                blockRanges: ranges.blockRanges,
                inlineRanges: ranges.inlineContentRanges,
                inlineDelimiterRanges: ranges.inlineDelimiterRanges,
                baseFont: textView.baseTextFont,
                baseColor: .labelColor,
                colorScheme: .dark
            )
        )
        textStorage.endEditing()
        textView.codeBlockBackgroundRanges = ranges.blockContentRanges
        textView.primeTextLayoutForDrawing()

        XCTAssertNil(textStorage.attribute(.backgroundColor, at: codeBlockRange.location, effectiveRange: nil))
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: codeBlockRange.location, effectiveRange: nil) as? NSColor, .clear)

        let contentRange = try XCTUnwrap(ranges.blockContentRanges.first)
        let backgroundRects = textView.codeBlockBackgroundRects(for: contentRange)
        XCTAssertEqual(backgroundRects.count, 1)

        let codeGlyphRange = layoutManager.glyphRange(
            forCharacterRange: (markdown as NSString).range(of: "let values"),
            actualCharacterRange: nil
        )
        let codeLineRect = layoutManager.boundingRect(forGlyphRange: codeGlyphRange, in: textContainer)
        let backgroundRect = try XCTUnwrap(backgroundRects.first)

        XCTAssertGreaterThan(backgroundRect.width, codeLineRect.width + 12)
        XCTAssertLessThan(backgroundRect.width, textView.bounds.width - (textView.textContainerInset.width * 2) - 80)
        XCTAssertGreaterThan(backgroundRect.height, codeLineRect.height * 1.8)
    }

    // `disablesAppKitDragDestination` is the opt-in toggle that keeps NSTextView out of
    // the drag-destination chain so a parent SwiftUI `.dropDestination` can receive
    // drops. Default must stay false so editors without a parent drop target (Skills
    // instructions, MCP headers/env) keep accepting drops. We stage some drag types
    // directly (NSTextView's own default registration depends on window attachment and
    // `isRichText` state that isn't present in a bare-test `frame: .zero` view); this
    // test only verifies the override — `updateDragTypeRegistration` unregisters when
    // the flag flips true and defers to `super.updateDragTypeRegistration()` when false.
    func testDisablesAppKitDragDestinationUnregistersDragTypesWhenEnabled() {
        let textView = AppKitTextView(frame: .zero)
        textView.registerForDraggedTypes([.string, .fileURL])
        XCTAssertEqual(Set(textView.registeredDraggedTypes), [.string, .fileURL])

        textView.disablesAppKitDragDestination = true
        XCTAssertTrue(textView.registeredDraggedTypes.isEmpty)
    }

    // Compact file-mention chips hide every stored glyph (clear foreground) and
    // shrink the chip rect via negative `.kern` per char so `AppKitTextView.drawCompactChipLabels`
    // can paint a decoded label over a tightly-sized rect. See
    // `Alveary/Views/Components/TextInput/AGENTS.md` for the rationale.
    func testCompactFileMentionStylingHidesStoredTextAndShrinksAdvanceViaKern() {
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

        let prefixColor = textStorage.attribute(.foregroundColor, at: 9, effectiveRange: nil) as? NSColor
        let suffixColor = textStorage.attribute(.foregroundColor, at: 30, effectiveRange: nil) as? NSColor
        let prefixKern = textStorage.attribute(.kern, at: 9, effectiveRange: nil) as? CGFloat
        let suffixKern = textStorage.attribute(.kern, at: 30, effectiveRange: nil) as? CGFloat

        XCTAssertEqual(prefixColor, .clear)
        XCTAssertEqual(suffixColor, .clear)
        XCTAssertNotNil(prefixKern)
        XCTAssertLessThan(prefixKern ?? 0, 0)
        XCTAssertEqual(prefixKern, suffixKern)
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
        textView.updateTextContainerForCurrentBounds()

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
        textView.updateTextContainerForCurrentBounds()

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

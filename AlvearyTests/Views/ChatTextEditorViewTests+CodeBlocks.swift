import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatTextEditorViewTests {
    func testConfigureAppliesFencedCodeBlockBackgroundRangesToNativeEditor() throws {
        let editor = makeEditor()
        let text = "Test\n```\nlet value = 1\nprint(value)"

        editor.configure(ChatTextEditorConfiguration(
            text: text,
            codeBlockRanges: AppMarkdownCodeBlockParser.blockRanges,
            inlineCodeBackgroundRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeDelimiterRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineDelimiterRanges }
        ))
        editor.layoutSubtreeIfNeeded()
        flushMainQueue()

        let textView = editor.textViewForTesting
        let blockContentRange = try XCTUnwrap(AppMarkdownCodeBlockParser.codeRanges(in: text).blockContentRanges.first)

        XCTAssertEqual(textView.codeBlockBackgroundRanges, [blockContentRange])
        let backgroundRect = try XCTUnwrap(textView.codeBlockBackgroundRects(for: blockContentRange).first)
        XCTAssertEqual(backgroundRect.minX, textView.textContainerInset.width + 0.5, accuracy: 0.5)
        XCTAssertLessThan(backgroundRect.width, textView.bounds.width - (textView.textContainerInset.width * 2) - 80)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let previousLineGlyphIndex = layoutManager.glyphIndexForCharacter(at: 0)
        let previousLineRect = layoutManager.lineFragmentRect(forGlyphAt: previousLineGlyphIndex, effectiveRange: nil)
        let previousLineMaxY = previousLineRect.maxY + textView.textContainerOrigin.y
        XCTAssertEqual(backgroundRect.minY - previousLineMaxY, 4, accuracy: 1)
        XCTAssertEqual(textView.textStorage?.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor, .clear)
    }

    func testClosedFencedCodeBlockKeepsOuterGapFromFollowingText() throws {
        let editor = makeEditor()
        let text = "Test\n```\nlet value = 1\n```\nAfter"

        editor.configure(ChatTextEditorConfiguration(
            text: text,
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
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let followingLineGlyphIndex = layoutManager.glyphIndexForCharacter(at: (text as NSString).range(of: "After").location)
        let followingLineRect = layoutManager.lineFragmentRect(forGlyphAt: followingLineGlyphIndex, effectiveRange: nil)
        let followingLineMinY = followingLineRect.minY + textView.textContainerOrigin.y

        XCTAssertEqual(followingLineMinY - backgroundRect.maxY, 4, accuracy: 1)
    }

    func testEmptyFencedCodeBlockMouseDownPlacesCaretInEditableContent() throws {
        let editor = makeEditor()
        let text = "Test\n```\n"

        editor.configure(ChatTextEditorConfiguration(
            text: text,
            selectedRange: NSRange(location: 0, length: 0),
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 140), styleMask: [], backing: .buffered, defer: false)
        window.contentView = editor
        editor.frame = window.contentView?.bounds ?? .zero
        editor.layoutSubtreeIfNeeded()
        flushMainQueue()

        let clickPoint = textView.convert(NSPoint(x: backgroundRect.midX, y: backgroundRect.midY), to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: clickPoint,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))

        textView.mouseDown(with: event)

        XCTAssertEqual(textView.selectedRange(), NSRange(location: blockRange.contentRange.location, length: 0))

        textView.perform(NSSelectorFromString("insertText:"), with: "let value = 1")
        editor.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(textView.string, "Test\n```\nlet value = 1")
        XCTAssertNotEqual(
            textView.textStorage?.attribute(.foregroundColor, at: blockRange.contentRange.location, effectiveRange: nil) as? NSColor,
            .clear
        )
    }

    func testEmptyFencedCodeBlockKeepsEditableLineHeight() throws {
        let editor = makeEditor()
        let text = "Test\n```\n"

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

        XCTAssertGreaterThan(backgroundRect.height, ChatTextEditor.primedLineHeight)
        XCTAssertEqual(textView.textStorage?.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertEqual((textView.typingAttributes[.foregroundColor] as? NSColor), .labelColor)
    }

    func testLeadingEmptyFencedCodeBlockStartsAtComposerTopInset() throws {
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

        XCTAssertEqual(backgroundRect.minY, textView.textContainerInset.height + 0.5, accuracy: 0.5)
    }

    func testLeadingEmptyFencedCodeBlockCaretUsesCodeContentTopInset() throws {
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
        let insertionPointRect = try XCTUnwrap(textView.emptyCodeBlockInsertionPointRect(from: proposedRect))
        let layoutManager = try XCTUnwrap(textView.layoutManager)

        XCTAssertEqual(
            insertionPointRect.minY,
            backgroundRect.minY + AppTextEditorCodeBlockStyling.codeBlockVerticalPadding,
            accuracy: 0.5
        )
        XCTAssertEqual(
            insertionPointRect.minX,
            backgroundRect.minX + AppTextEditorCodeBlockStyling.codeBlockHorizontalPadding,
            accuracy: 0.5
        )
        XCTAssertEqual(
            insertionPointRect.height,
            ceil(layoutManager.defaultLineHeight(for: textView.baseTextFont)),
            accuracy: 0.5
        )
    }

    func testLeadingNonEmptyFencedCodeBlockKeepsSymmetricInternalPadding() throws {
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

        let textView = editor.textViewForTesting
        let blockContentRange = try XCTUnwrap(AppMarkdownCodeBlockParser.codeRanges(in: text).blockContentRanges.first)
        let backgroundRect = try XCTUnwrap(textView.codeBlockBackgroundRects(for: blockContentRange).first)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)

        let glyphRange = layoutManager.glyphRange(forCharacterRange: blockContentRange, actualCharacterRange: nil)
        let contentLineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        let contentLineMinY = contentLineRect.minY + textView.textContainerOrigin.y

        XCTAssertEqual(backgroundRect.minY, textView.textContainerInset.height + 0.5, accuracy: 0.5)
        XCTAssertEqual(
            contentLineMinY - backgroundRect.minY,
            AppTextEditorCodeBlockStyling.codeBlockVerticalPadding,
            accuracy: 1
        )
    }

    func testEmptyTextResetsCodeBlockTypingIndentForPlaceholderCaret() {
        let textView = AppKitTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 80))
        textView.baseTextFont = .preferredFont(forTextStyle: .body)
        textView.typingAttributes = AppTextEditorCodeBlockStyling.codeBlockAttributes(
            font: textView.baseTextFont,
            colorScheme: .dark
        )

        textView.string = ""
        textView.didChangeText()

        let paragraphStyle = textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(paragraphStyle?.firstLineHeadIndent ?? 0, 0)
        XCTAssertEqual(paragraphStyle?.headIndent ?? 0, 0)
    }

    func testBackspaceAtCodeBlockContentStartRemovesOpenFence() throws {
        let editor = makeEditor()
        let text = "Test\n```\nfff"
        var changedText: String?

        editor.configure(ChatTextEditorConfiguration(
            text: text,
            codeBlockRanges: AppMarkdownCodeBlockParser.blockRanges,
            inlineCodeBackgroundRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeDelimiterRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineDelimiterRanges },
            onTextChange: { changedText = $0 }
        ))
        editor.layoutSubtreeIfNeeded()
        flushMainQueue()

        let textView = editor.textViewForTesting
        let blockRange = try XCTUnwrap(AppMarkdownCodeBlockParser.blockCodeRanges(in: text).first)
        textView.setSelectedRange(NSRange(location: blockRange.contentRange.location, length: 0))

        textView.deleteBackward(nil)

        XCTAssertEqual(changedText, "Test\nfff")
        XCTAssertEqual(textView.string, "Test\nfff")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: (text as NSString).range(of: "```").location, length: 0))
        XCTAssertTrue(textView.codeBlockBackgroundRanges.isEmpty)
    }

    func testBackspaceAtCodeBlockContentStartRemovesClosedFence() throws {
        let editor = makeEditor()
        let text = "Test\n```\nfff\n```\nAfter"
        var changedText: String?

        editor.configure(ChatTextEditorConfiguration(
            text: text,
            codeBlockRanges: AppMarkdownCodeBlockParser.blockRanges,
            inlineCodeBackgroundRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeDelimiterRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineDelimiterRanges },
            onTextChange: { changedText = $0 }
        ))
        editor.layoutSubtreeIfNeeded()
        flushMainQueue()

        let textView = editor.textViewForTesting
        let blockRange = try XCTUnwrap(AppMarkdownCodeBlockParser.blockCodeRanges(in: text).first)
        textView.setSelectedRange(NSRange(location: blockRange.contentRange.location, length: 0))

        textView.deleteBackward(nil)

        XCTAssertEqual(changedText, "Test\nfff\nAfter")
        XCTAssertEqual(textView.string, "Test\nfff\nAfter")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: (text as NSString).range(of: "```").location, length: 0))
        XCTAssertTrue(textView.codeBlockBackgroundRanges.isEmpty)
    }

    func testBackspaceBelowClosedCodeBlockRemovesOutsideLineWithoutEditingHiddenFence() throws {
        let editor = makeEditor()
        let text = "Test\n```\nfff\n```\n"
        var changedText: String?

        editor.configure(ChatTextEditorConfiguration(
            text: text,
            selectedRange: NSRange(location: (text as NSString).length, length: 0),
            codeBlockRanges: AppMarkdownCodeBlockParser.blockRanges,
            inlineCodeBackgroundRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeDelimiterRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineDelimiterRanges },
            onTextChange: { changedText = $0 }
        ))
        editor.layoutSubtreeIfNeeded()
        flushMainQueue()

        let textView = editor.textViewForTesting
        textView.deleteBackward(nil)

        let expectedText = "Test\n```\nfff\n```"
        XCTAssertEqual(changedText, expectedText)
        XCTAssertEqual(textView.string, expectedText)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: (expectedText as NSString).length, length: 0))
        let delimiterRange = try XCTUnwrap(AppMarkdownCodeBlockParser.blockCodeRanges(in: expectedText).first?.delimiterRanges.last)
        XCTAssertEqual((expectedText as NSString).substring(with: delimiterRange), "```")
        XCTAssertFalse(textView.hiddenCodeBlockDelimiterRects().isEmpty)
    }

    func testBackspaceFromNormalizedClosingFenceBoundaryRemovesOutsideLine() throws {
        let editor = makeEditor()
        let text = "Test\n```\nfff\n```\n"
        var changedText: String?

        editor.configure(ChatTextEditorConfiguration(
            text: text,
            codeBlockRanges: AppMarkdownCodeBlockParser.blockRanges,
            inlineCodeBackgroundRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeDelimiterRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineDelimiterRanges },
            onTextChange: { changedText = $0 }
        ))
        editor.layoutSubtreeIfNeeded()
        flushMainQueue()

        let textView = editor.textViewForTesting
        let blockRange = try XCTUnwrap(AppMarkdownCodeBlockParser.blockCodeRanges(in: text).first)
        textView.setSelectedRangeWithoutCodeBlockNormalization(NSRange(location: NSMaxRange(blockRange.contentRange), length: 0))

        textView.deleteBackward(nil)

        let expectedText = "Test\n```\nfff\n```"
        XCTAssertEqual(changedText, expectedText)
        XCTAssertEqual(textView.string, expectedText)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: (expectedText as NSString).length, length: 0))
    }

    func testTypingFromHiddenCodeBlockDelimiterInsertsVisibleCodeText() throws {
        let editor = makeEditor()
        let text = "Test\n```\n"

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
        textView.setSelectedRange(NSRange(location: blockRange.delimiterRanges[0].location + 1, length: 0))

        XCTAssertEqual(textView.selectedRange(), NSRange(location: blockRange.contentRange.location, length: 0))

        textView.insertText("let value = 1", replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        let insertedRange = NSRange(location: blockRange.contentRange.location, length: 13)
        XCTAssertEqual(textView.string, "Test\n```\nlet value = 1")
        XCTAssertNotEqual(
            textView.textStorage?.attribute(.foregroundColor, at: insertedRange.location, effectiveRange: nil) as? NSColor,
            .clear
        )
        XCTAssertEqual(
            textView.textStorage?.attribute(.font, at: insertedRange.location, effectiveRange: nil) as? NSFont,
            AppTextEditorCodeBlockStyling.codeBlockAttributes(font: textView.baseTextFont, colorScheme: .dark)[.font] as? NSFont
        )
    }

    func testKeyboardInsertTextAtOpenCodeBlockEndUsesVisibleCodeAttributes() throws {
        let editor = makeEditor()
        let text = "Test\n```\n"

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
        textView.perform(NSSelectorFromString("insertText:"), with: "let value = 1")
        editor.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        let insertedLocation = (text as NSString).length
        XCTAssertEqual(textView.string, "Test\n```\nlet value = 1")
        XCTAssertNotEqual(
            textView.textStorage?.attribute(.foregroundColor, at: insertedLocation, effectiveRange: nil) as? NSColor,
            .clear
        )
    }

    func testKeyboardInsertAtEmptyCodeBoundaryOverridesStaleHiddenDelimiterTypingAttributes() {
        let editor = makeEditor()
        let text = "Test\n```\n"

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
        textView.typingAttributes = AppTextEditorCodeBlockStyling.codeBlockDelimiterAttributes(font: textView.baseTextFont)

        textView.perform(NSSelectorFromString("insertText:"), with: "let value = 1")
        editor.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        let insertedLocation = (text as NSString).length
        XCTAssertEqual(textView.string, "Test\n```\nlet value = 1")
        XCTAssertNotEqual(
            textView.textStorage?.attribute(.foregroundColor, at: insertedLocation, effectiveRange: nil) as? NSColor,
            .clear
        )
        XCTAssertNotEqual(textView.typingAttributes[.foregroundColor] as? NSColor, .clear)
    }

    func testTypingFenceThenCodeKeepsCaretInEditableCodeContent() {
        let editor = makeEditor()
        var currentText = ""
        var currentSelection: NSRange?

        let configureEditor = {
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
            self.flushMainQueue()
        }

        configureEditor()
        let textView = editor.textViewForTesting
        textView.perform(NSSelectorFromString("insertText:"), with: "Test\n```")
        editor.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        configureEditor()

        XCTAssertEqual(currentText, "Test\n```\n")
        XCTAssertEqual(currentSelection, NSRange(location: ("Test\n```\n" as NSString).length, length: 0))
        XCTAssertNotEqual(textView.typingAttributes[.foregroundColor] as? NSColor, .clear)

        textView.perform(NSSelectorFromString("insertText:"), with: "let value = 1")
        editor.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        configureEditor()

        XCTAssertEqual(currentText, "Test\n```\nlet value = 1")
        let codeInsertionLocation = ("Test\n```\n" as NSString).length
        XCTAssertNotEqual(
            textView.textStorage?.attribute(.foregroundColor, at: codeInsertionLocation, effectiveRange: nil) as? NSColor,
            .clear
        )
    }

}

import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitChatSurfaceViewTests {
    func testComposerBodyReturnStillSubmitsInsideCodeBlock() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let text = "Test\n```\nlet value = 1"
        var submitCount = 0
        body.configure(makeComposerCodeBlockBodyConfiguration(text: text, onSubmit: {
            submitCount += 1
        }))
        body.selectedRange = NSRange(location: (text as NSString).length, length: 0)

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .return, modifiers: [])), .handled)

        XCTAssertEqual(submitCount, 1)
        XCTAssertEqual(body.editorView.textViewForTesting.string, text)
    }

    func testComposerBodyShiftReturnInsertsLineBreakInsideOpenCodeBlock() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let text = "Test\n```\nlet value = 1"
        var changedText: String?
        var submitCount = 0
        body.configure(makeComposerCodeBlockBodyConfiguration(text: text, onTextChange: {
            changedText = $0
        }, onSubmit: {
            submitCount += 1
        }))
        body.selectedRange = NSRange(location: (text as NSString).length, length: 0)

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .return, modifiers: .shift)), .handled)

        XCTAssertEqual(submitCount, 0)
        XCTAssertEqual(changedText, "Test\n```\nlet value = 1\n")
        XCTAssertEqual(body.editorView.textViewForTesting.string, "Test\n```\nlet value = 1\n")
        XCTAssertEqual(body.selectedRange, NSRange(location: ("Test\n```\nlet value = 1\n" as NSString).length, length: 0))
    }

    func testComposerBodyShiftReturnAcceptsInertNumericPadModifierInsideOpenCodeBlock() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let text = "Test\n```\nlet value = 1"
        var changedText: String?
        body.configure(makeComposerCodeBlockBodyConfiguration(text: text, onTextChange: {
            changedText = $0
        }))
        body.selectedRange = NSRange(location: (text as NSString).length, length: 0)

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .return, modifiers: [.shift, .numericPad])), .handled)

        XCTAssertEqual(changedText, "Test\n```\nlet value = 1\n")
        XCTAssertEqual(body.selectedRange, NSRange(location: ("Test\n```\nlet value = 1\n" as NSString).length, length: 0))
    }

    func testComposerBodyShiftReturnInsertsLineBreakInsideClosedCodeBlock() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let text = "Test\n```\nlet value = 1\n```\nAfter"
        var changedText: String?
        var submitCount = 0
        body.configure(makeComposerCodeBlockBodyConfiguration(text: text, onTextChange: {
            changedText = $0
        }, onSubmit: {
            submitCount += 1
        }))
        let insertionLocation = ("Test\n```\nlet value = 1" as NSString).length
        body.selectedRange = NSRange(location: insertionLocation, length: 0)

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .return, modifiers: .shift)), .handled)

        XCTAssertEqual(submitCount, 0)
        XCTAssertEqual(changedText, "Test\n```\nlet value = 1\n\n```\nAfter")
        XCTAssertEqual(body.selectedRange, NSRange(location: insertionLocation + 1, length: 0))
    }

    func testComposerBodyTypingFenceThenCodeKeepsCodeInputVisible() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        var modelText = ""
        body.configure(makeComposerCodeBlockBodyConfiguration(text: modelText, onTextChange: {
            modelText = $0
        }))
        body.layoutSubtreeIfNeeded()

        let textView = body.editorView.textViewForTesting
        textView.perform(NSSelectorFromString("insertText:"), with: "Test\n```")
        body.editorView.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        body.configure(makeComposerCodeBlockBodyConfiguration(text: modelText, onTextChange: {
            modelText = $0
        }))
        body.layoutSubtreeIfNeeded()

        textView.perform(NSSelectorFromString("insertText:"), with: "let value = 1")
        body.editorView.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        body.configure(makeComposerCodeBlockBodyConfiguration(text: modelText, onTextChange: {
            modelText = $0
        }))

        let insertedLocation = ("Test\n```\n" as NSString).length
        XCTAssertEqual(modelText, "Test\n```\nlet value = 1")
        XCTAssertNotEqual(
            textView.textStorage?.attribute(.foregroundColor, at: insertedLocation, effectiveRange: nil) as? NSColor,
            .clear
        )
        XCTAssertEqual(body.selectedRange, NSRange(location: (modelText as NSString).length, length: 0))
    }

    func testComposerBodyDownArrowExitsOpenCodeBlock() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let text = "Test\n```\nlet value = 1"
        var changedText: String?
        body.configure(makeComposerCodeBlockBodyConfiguration(text: text, onTextChange: {
            changedText = $0
        }))
        body.selectedRange = NSRange(location: (text as NSString).length, length: 0)

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .downArrow, modifiers: [])), .handled)

        let expectedText = "Test\n```\nlet value = 1\n```\n"
        XCTAssertEqual(changedText, expectedText)
        XCTAssertEqual(body.editorView.textViewForTesting.string, expectedText)
        XCTAssertEqual(body.selectedRange, NSRange(location: (expectedText as NSString).length, length: 0))
        XCTAssertFalse(expectedText.hasSuffix("\n\n"))
        let paragraphStyle = body.editorView.textViewForTesting.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(paragraphStyle?.firstLineHeadIndent, 0)
        XCTAssertEqual(paragraphStyle?.headIndent, 0)
    }

    func testComposerBodyTypingAfterDownArrowExitKeepsOutsideTextBelowCodeBlock() throws {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        var modelText = "Test\n```\nlet value = 1"
        body.configure(makeComposerCodeBlockBodyConfiguration(text: modelText, onTextChange: {
            modelText = $0
        }))
        body.layoutSubtreeIfNeeded()
        body.selectedRange = NSRange(location: (modelText as NSString).length, length: 0)

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .downArrow, modifiers: [])), .handled)
        body.configure(makeComposerCodeBlockBodyConfiguration(text: modelText, onTextChange: {
            modelText = $0
        }))
        body.layoutSubtreeIfNeeded()

        let textView = body.editorView.textViewForTesting
        textView.perform(NSSelectorFromString("insertText:"), with: "Hi")
        body.editorView.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        body.configure(makeComposerCodeBlockBodyConfiguration(text: modelText, onTextChange: {
            modelText = $0
        }))
        body.layoutSubtreeIfNeeded()

        XCTAssertEqual(modelText, "Test\n```\nlet value = 1\n```\nHi")
        let blockRange = try XCTUnwrap(AppMarkdownCodeBlockParser.blockCodeRanges(in: modelText).first)
        let backgroundRect = try XCTUnwrap(textView.codeBlockBackgroundRects(for: blockRange.contentRange).first)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let outsideGlyphIndex = layoutManager.glyphIndexForCharacter(at: (modelText as NSString).range(of: "Hi").location)
        let outsideLineRect = layoutManager.lineFragmentRect(forGlyphAt: outsideGlyphIndex, effectiveRange: nil)
        let outsideLineMinY = outsideLineRect.minY + textView.textContainerOrigin.y

        XCTAssertEqual(outsideLineMinY - backgroundRect.maxY, AppTextEditorCodeBlockStyling.codeBlockOuterGap, accuracy: 0.5)
        let paragraphStyle = textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(paragraphStyle?.firstLineHeadIndent, 0)
        XCTAssertEqual(paragraphStyle?.headIndent, 0)
    }

    func testComposerBodyUpArrowAfterDownArrowReentersCodeBlockBeforeClosingFence() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let text = "Test\n```\nlet value = 1"
        body.configure(makeComposerCodeBlockBodyConfiguration(text: text))
        body.selectedRange = NSRange(location: (text as NSString).length, length: 0)

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .downArrow, modifiers: [])), .handled)
        let textAfterExit = body.editorView.textViewForTesting.string
        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .upArrow, modifiers: [])), .handled)

        let blockRange = AppMarkdownCodeBlockParser.blockCodeRanges(in: textAfterExit)[0]
        XCTAssertEqual(body.editorView.textViewForTesting.string, textAfterExit)
        XCTAssertEqual(body.selectedRange, NSRange(location: NSMaxRange(blockRange.contentRange) - 1, length: 0))
    }

    func testComposerBodyUpArrowFromEndOfTrailingBlankLineReentersCodeBlockBeforeClosingFence() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let text = "Test\n```\nlet value = 1\n```\n"
        body.configure(makeComposerCodeBlockBodyConfiguration(text: text))
        body.selectedRange = NSRange(location: (text as NSString).length, length: 0)

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .upArrow, modifiers: [])), .handled)

        let blockRange = AppMarkdownCodeBlockParser.blockCodeRanges(in: text)[0]
        XCTAssertEqual(body.editorView.textViewForTesting.string, text)
        XCTAssertEqual(body.selectedRange, NSRange(location: NSMaxRange(blockRange.contentRange) - 1, length: 0))
    }

    func testComposerBodyDownArrowAcceptsInertNumericPadModifierInsideCodeBlock() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let text = "Test\n```\nlet value = 1"
        var changedText: String?
        body.configure(makeComposerCodeBlockBodyConfiguration(text: text, onTextChange: {
            changedText = $0
        }))
        body.selectedRange = NSRange(location: (text as NSString).length, length: 0)

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .downArrow, modifiers: .numericPad)), .handled)

        let expectedText = "Test\n```\nlet value = 1\n```\n"
        XCTAssertEqual(changedText, expectedText)
        XCTAssertEqual(body.selectedRange, NSRange(location: (expectedText as NSString).length, length: 0))
    }

    func testComposerBodyDownArrowDoesNotExitOpenCodeBlockBeforeLastLine() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let text = "Test\n```\nlet value = 1\nprint(value)"
        var changedText: String?
        body.configure(makeComposerCodeBlockBodyConfiguration(text: text, onTextChange: {
            changedText = $0
        }))
        body.selectedRange = NSRange(location: ("Test\n```\nlet value".count), length: 0)

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .downArrow, modifiers: [])), .ignored)

        XCTAssertNil(changedText)
        XCTAssertEqual(body.editorView.textViewForTesting.string, text)
        XCTAssertEqual(body.selectedRange, NSRange(location: ("Test\n```\nlet value".count), length: 0))
    }

    func testComposerBodyDownArrowExitsOpenCodeBlockFromLastLine() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let text = "Test\n```\nlet value = 1\nprint(value)"
        var changedText: String?
        body.configure(makeComposerCodeBlockBodyConfiguration(text: text, onTextChange: {
            changedText = $0
        }))
        body.selectedRange = NSRange(location: ("Test\n```\nlet value = 1\nprint".count), length: 0)

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .downArrow, modifiers: [])), .handled)

        let expectedText = "Test\n```\nlet value = 1\nprint(value)\n```\n"
        XCTAssertEqual(changedText, expectedText)
        XCTAssertEqual(body.editorView.textViewForTesting.string, expectedText)
        XCTAssertEqual(body.selectedRange, NSRange(location: (expectedText as NSString).length, length: 0))
    }

    func testComposerBodyDownArrowFromClosedMultilineCodeBlockUsesExistingLineBelow() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let text = "Intro\n```\nlet value = 1\nprint(value)\n```\nAfter"
        body.configure(makeComposerCodeBlockBodyConfiguration(text: text))
        let blockRange = AppMarkdownCodeBlockParser.blockCodeRanges(in: text)[0]
        body.selectedRange = NSRange(location: ("Intro\n```\nlet value = 1\nprint".count), length: 0)

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .downArrow, modifiers: [])), .handled)

        let closingDelimiter = blockRange.delimiterRanges[1]
        XCTAssertEqual(body.editorView.textViewForTesting.string, text)
        XCTAssertEqual(body.selectedRange, NSRange(location: NSMaxRange(closingDelimiter), length: 0))
    }

    func testComposerBodyDownArrowFromInsertedLineAboveTopCodeBlockSkipsOpeningFence() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let text = "\n```\nlet value = 1"
        body.configure(makeComposerCodeBlockBodyConfiguration(text: text))
        body.selectedRange = NSRange(location: 0, length: 0)

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .downArrow, modifiers: [])), .handled)

        let blockRange = AppMarkdownCodeBlockParser.blockCodeRanges(in: text)[0]
        XCTAssertEqual(body.editorView.textViewForTesting.string, text)
        XCTAssertEqual(body.selectedRange, NSRange(location: blockRange.contentRange.location, length: 0))
    }

    func testComposerBodyDownArrowFromLineAboveCodeBlockSkipsOpeningFence() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let text = "Intro\n```\nlet value = 1"
        body.configure(makeComposerCodeBlockBodyConfiguration(text: text))
        body.selectedRange = NSRange(location: 5, length: 0)

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .downArrow, modifiers: [])), .handled)

        let blockRange = AppMarkdownCodeBlockParser.blockCodeRanges(in: text)[0]
        XCTAssertEqual(body.editorView.textViewForTesting.string, text)
        XCTAssertEqual(body.selectedRange, NSRange(location: blockRange.contentRange.location, length: 0))
    }

    func testComposerBodyDownArrowFromStartOfLineAboveCodeBlockSkipsOpeningFence() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let text = "Intro\n```\nlet value = 1"
        body.configure(makeComposerCodeBlockBodyConfiguration(text: text))
        body.selectedRange = NSRange(location: 0, length: 0)

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .downArrow, modifiers: [])), .handled)

        let blockRange = AppMarkdownCodeBlockParser.blockCodeRanges(in: text)[0]
        XCTAssertEqual(body.editorView.textViewForTesting.string, text)
        XCTAssertEqual(body.selectedRange, NSRange(location: blockRange.contentRange.location, length: 0))
    }

    func testComposerBodyUpArrowFromLineBelowCodeBlockSkipsClosingFence() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let text = "```\nlet value = 1\n```\nAfter"
        body.configure(makeComposerCodeBlockBodyConfiguration(text: text))
        let blockRange = AppMarkdownCodeBlockParser.blockCodeRanges(in: text)[0]
        body.selectedRange = NSRange(location: NSMaxRange(blockRange.delimiterRanges[1]), length: 0)

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .upArrow, modifiers: [])), .handled)

        XCTAssertEqual(body.editorView.textViewForTesting.string, text)
        XCTAssertEqual(body.selectedRange, NSRange(location: NSMaxRange(blockRange.contentRange) - 1, length: 0))
    }

    func testComposerBodyUpArrowExitsCodeBlockAboveExistingPrefix() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let text = "Intro\n```\nlet value = 1"
        body.configure(makeComposerCodeBlockBodyConfiguration(text: text))
        body.selectedRange = NSRange(location: 10, length: 0)

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .upArrow, modifiers: [])), .handled)

        XCTAssertEqual(body.editorView.textViewForTesting.string, text)
        XCTAssertEqual(body.selectedRange, NSRange(location: 5, length: 0))
    }

    func testComposerBodyUpArrowAcceptsInertNumericPadModifierInsideCodeBlock() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let text = "Intro\n```\nlet value = 1"
        body.configure(makeComposerCodeBlockBodyConfiguration(text: text))
        body.selectedRange = NSRange(location: 10, length: 0)

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .upArrow, modifiers: .numericPad)), .handled)

        XCTAssertEqual(body.editorView.textViewForTesting.string, text)
        XCTAssertEqual(body.selectedRange, NSRange(location: 5, length: 0))
    }

    func testComposerBodyUpArrowWithSelectionModifierDoesNotExitCodeBlock() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let text = "Intro\n```\nlet value = 1"
        body.configure(makeComposerCodeBlockBodyConfiguration(text: text))
        body.selectedRange = NSRange(location: 10, length: 0)

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .upArrow, modifiers: .shift)), .ignored)

        XCTAssertEqual(body.editorView.textViewForTesting.string, text)
        XCTAssertEqual(body.selectedRange, NSRange(location: 10, length: 0))
    }

    func testComposerBodyUpArrowExitsCodeBlockFromFirstLine() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let text = "Intro\n```\nlet value = 1\nprint(value)"
        body.configure(makeComposerCodeBlockBodyConfiguration(text: text))
        body.selectedRange = NSRange(location: ("Intro\n```\nlet value".count), length: 0)

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .upArrow, modifiers: [])), .handled)

        XCTAssertEqual(body.editorView.textViewForTesting.string, text)
        XCTAssertEqual(body.selectedRange, NSRange(location: 5, length: 0))
    }

    func testComposerBodyUpArrowDoesNotExitCodeBlockAfterFirstLine() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let text = "Intro\n```\nlet value = 1\nprint(value)\nreturn value"
        body.configure(makeComposerCodeBlockBodyConfiguration(text: text))
        body.selectedRange = NSRange(location: ("Intro\n```\nlet value = 1\nprint".count), length: 0)

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .upArrow, modifiers: [])), .ignored)

        XCTAssertEqual(body.editorView.textViewForTesting.string, text)
        XCTAssertEqual(body.selectedRange, NSRange(location: ("Intro\n```\nlet value = 1\nprint".count), length: 0))
    }

    func testComposerBodyUpArrowExitsTopCodeBlockByInsertingBlankLine() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let text = "```\nlet value = 1"
        var changedText: String?
        body.configure(makeComposerCodeBlockBodyConfiguration(text: text, onTextChange: {
            changedText = $0
        }))
        body.selectedRange = NSRange(location: 4, length: 0)

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .upArrow, modifiers: [])), .handled)

        let expectedText = "\n```\nlet value = 1"
        XCTAssertEqual(changedText, expectedText)
        XCTAssertEqual(body.editorView.textViewForTesting.string, expectedText)
        XCTAssertEqual(body.selectedRange, NSRange(location: 0, length: 0))
    }
}

private func makeComposerCodeBlockBodyConfiguration(
    text: String,
    onTextChange: @escaping (String) -> Void = { _ in },
    onSubmit: @escaping () -> Void = {}
) -> AppKitChatComposerBodyConfiguration {
    AppKitChatComposerBodyConfiguration(
        text: text,
        mode: .idle,
        defaultEnterBehavior: .queue,
        isStopConfirmationArmed: false,
        supportsMidTurnSteering: true,
        isProjectTrustBlocked: false,
        isHandoffSteeringPromptActive: false,
        isHandoffOutputPromptActive: false,
        handoffSteeringCountdown: nil,
        sendCountdown: nil,
        hasQueuedMessages: false,
        hasTopContent: false,
        workingDirectory: "/tmp/alveary",
        requestFirstResponder: nil,
        colorScheme: .dark,
        loadFileCompletions: { [] },
        loadSkillCompletions: { [] },
        onTextChange: onTextChange,
        onSubmit: onSubmit,
        onSteer: {},
        onStop: {},
        onStopConfirmationChange: { _ in },
        onFocusRequestConsumed: { _ in }
    )
}

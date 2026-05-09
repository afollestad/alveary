import AppKit
import XCTest

@testable import Alveary

@MainActor
final class ChatTextEditorViewTests: XCTestCase {
    func testConfigureOwnsTextViewStateDirectly() throws {
        let editor = makeEditor()

        editor.configure(ChatTextEditorConfiguration(
            text: "Review @Alveary/Views/Input/ChatInputField.swift",
            placeholder: "Ask anything",
            textChips: ChatInputFieldTextSupport.composerTextChips(in:),
            codeBlockRanges: AppMarkdownCodeBlockParser.blockRanges,
            inlineCodeBackgroundRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeDelimiterRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineDelimiterRanges }
        ))
        editor.layoutSubtreeIfNeeded()

        let textView = editor.textViewForTesting
        XCTAssertEqual(textView.string, "Review @Alveary/Views/Input/ChatInputField.swift")
        XCTAssertEqual(textView.placeholder, "Ask anything")
        XCTAssertEqual(textView.textChips.count, 1)
        let scrollView = try XCTUnwrap(editor.subviews.first as? NSScrollView)
        XCTAssertFalse(scrollView.drawsBackground)
        XCTAssertFalse(scrollView.contentView.drawsBackground)
        XCTAssertFalse(textView.drawsBackground)
        XCTAssertTrue(textView.allowsUndo)
    }

    func testConfigureWithCompactFileMentionAppliesChipAttributesOutsideTextStorageEdit() {
        let editor = makeEditor()
        let text = "Review @/Users/alice/Development/Project/Chat%20Input.swift"

        editor.configure(ChatTextEditorConfiguration(
            text: text,
            textChips: ChatInputFieldTextSupport.composerTextChips(in:)
        ))
        editor.layoutSubtreeIfNeeded()

        let textView = editor.textViewForTesting
        let chip = textView.textChips[0]
        XCTAssertGreaterThan(textView.frame.width, 0)
        XCTAssertGreaterThan(textView.textContainer?.containerSize.width ?? 0, 0)
        XCTAssertEqual(textView.textChipDisplayMode(for: chip), .compactLabel("@Chat%20Input.swift"))
        XCTAssertEqual(
            textView.textStorage?.attribute(.foregroundColor, at: chip.range.location, effectiveRange: nil) as? NSColor,
            .clear
        )
    }

    func testWrappedFileMentionKeepsStoredTextVisible() {
        let editor = ChatTextEditorView(frame: NSRect(x: 0, y: 0, width: 150, height: 160))
        let text = "Review @/Users/alice/Development/Project/VeryLongFileNameThatCannotFitInTheComposer.swift"

        editor.configure(ChatTextEditorConfiguration(
            text: text,
            textChips: ChatInputFieldTextSupport.composerTextChips(in:)
        ))
        editor.layoutSubtreeIfNeeded()
        flushMainQueue()

        let textView = editor.textViewForTesting
        let chip = textView.textChips[0]
        XCTAssertGreaterThan(textView.textChipRects(for: chip.range).count, 1)
        XCTAssertEqual(textView.textChipDisplayMode(for: chip), .fullText)
        XCTAssertNotEqual(
            textView.textStorage?.attribute(.foregroundColor, at: chip.range.location, effectiveRange: nil) as? NSColor,
            .clear
        )
    }

    func testConfigureWithChipBeforeLayoutDefersCompactMeasurementUntilWidthExists() {
        let editor = ChatTextEditorView(frame: .zero)
        let text = "Review @/Users/alice/Development/Project/Chat%20Input.swift"

        editor.configure(ChatTextEditorConfiguration(
            text: text,
            textChips: ChatInputFieldTextSupport.composerTextChips(in:)
        ))

        let textView = editor.textViewForTesting
        let chip = textView.textChips[0]
        XCTAssertEqual(textView.textChipDisplayMode(for: chip), .fullText)
    }

    func testConfigureWithTextPrimesLayoutForImmediateDrawAfterLayout() {
        let editor = makeEditor()

        editor.configure(ChatTextEditorConfiguration(
            text: "Investigate the flaky login flow and summarize what changed."
        ))
        editor.layoutSubtreeIfNeeded()

        XCTAssertTrue(editor.textViewForTesting.isTextLayoutReadyForDrawingForTesting)
    }

    func testRepeatedConfigureDoesNotReapplyTypingAttributesWhenInputsAreUnchanged() {
        let editor = makeEditor()
        let configuration = ChatTextEditorConfiguration(
            text: "Review `inline code` and @/Users/alice/Development/Project/Chat%20Input.swift",
            textChips: ChatInputFieldTextSupport.composerTextChips(in:),
            codeBlockRanges: AppMarkdownCodeBlockParser.blockRanges,
            inlineCodeBackgroundRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeDelimiterRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineDelimiterRanges }
        )

        editor.configure(configuration)
        flushMainQueue()
        let textPresentationApplications = editor.presentationApplyCountForTesting
        let typingAttributeApplications = editor.typingAttrsApplyCountForTesting

        editor.configure(configuration)
        flushMainQueue()

        XCTAssertEqual(editor.presentationApplyCountForTesting, textPresentationApplications)
        XCTAssertEqual(editor.typingAttrsApplyCountForTesting, typingAttributeApplications)
    }

    func testTextViewPrimesContainerWidthBeforeLayoutDependentDrawing() {
        let textView = AppKitTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 80))
        textView.string = "Use `code`"
        textView.inlineCodeBackgroundRanges = [NSRange(location: 4, length: 4)]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        XCTAssertTrue(textView.updateTextContainerForCurrentBounds())
        XCTAssertTrue(textView.prepareForSafeTextLayout())
        XCTAssertFalse(textView.canDrawTextLayoutSafely())
        XCTAssertTrue(textView.primeTextLayoutForDrawing())
        XCTAssertTrue(textView.canDrawTextLayoutSafely())
        XCTAssertEqual(textView.textContainer?.containerSize.width ?? 0, 240, accuracy: 0.5)
        XCTAssertEqual(textView.layoutManager?.allowsNonContiguousLayout, false)
    }

    func testTextViewPrimesContainerWidthUsingTextInsets() {
        let textView = AppKitTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 80))
        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.textContainer?.containerSize = NSSize(width: 240, height: CGFloat.greatestFiniteMagnitude)

        XCTAssertTrue(textView.updateTextContainerForCurrentBounds())
        XCTAssertTrue(textView.prepareForSafeTextLayout())
        XCTAssertEqual(textView.textContainer?.containerSize.width ?? 0, 220, accuracy: 0.5)
    }

    func testTextViewWidthChangeInvalidatesDrawReadinessUntilPrimed() {
        let textView = AppKitTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 80))
        textView.string = "Use `code`"
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        XCTAssertTrue(textView.updateTextContainerForCurrentBounds())
        XCTAssertTrue(textView.primeTextLayoutForDrawing())
        XCTAssertTrue(textView.isTextLayoutReadyForDrawingForTesting)

        textView.frame.size.width = 300

        XCTAssertTrue(textView.updateTextContainerForCurrentBounds())
        XCTAssertFalse(textView.isTextLayoutReadyForDrawingForTesting)
        XCTAssertFalse(textView.canDrawTextLayoutSafely())
    }

    func testTypedTextChangeLeavesLayoutPrimedForNextDraw() {
        let editor = makeEditor()
        editor.configure(ChatTextEditorConfiguration(
            text: "Before",
            inlineCodeBackgroundRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeDelimiterRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineDelimiterRanges }
        ))
        flushMainQueue()

        let textView = editor.textViewForTesting
        textView.string = "After `code`"
        textView.didChangeText()

        XCTAssertTrue(textView.isTextLayoutReadyForDrawingForTesting)
    }

    func testDeferredHeightMeasurementRefreshesWidthDependentChipStyling() {
        let editor = ChatTextEditorView(frame: .zero)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 96), styleMask: [], backing: .buffered, defer: false)
        let text = "Review @/Users/alice/Development/Project/Chat%20Input.swift"

        editor.configure(ChatTextEditorConfiguration(
            text: text,
            textChips: ChatInputFieldTextSupport.composerTextChips(in:)
        ))
        window.contentView = editor
        editor.frame = NSRect(x: 0, y: 0, width: 420, height: 96)
        editor.layoutSubtreeIfNeeded()
        flushMainQueue()

        let textView = editor.textViewForTesting
        let chip = textView.textChips[0]
        XCTAssertEqual(textView.textChipDisplayMode(for: chip), .compactLabel("@Chat%20Input.swift"))
        XCTAssertEqual(
            textView.textStorage?.attribute(.foregroundColor, at: chip.range.location, effectiveRange: nil) as? NSColor,
            .clear
        )
    }

    func testTextChangeReportsUpdatedDraft() {
        let editor = makeEditor()
        var reportedText: String?
        editor.configure(ChatTextEditorConfiguration(
            text: "Before",
            onTextChange: { reportedText = $0 }
        ))

        editor.textViewForTesting.string = "After"
        editor.textDidChange(Notification(name: NSText.didChangeNotification, object: editor.textViewForTesting))

        XCTAssertEqual(reportedText, "After")
    }

    func testSelectionChangeReportsUTF16Range() {
        let editor = makeEditor()
        var reportedRange: NSRange?
        editor.configure(ChatTextEditorConfiguration(
            text: "Before",
            onSelectionChange: { reportedRange = $0 }
        ))

        editor.textViewForTesting.setSelectedRange(NSRange(location: 2, length: 3))
        editor.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: editor.textViewForTesting)
        )

        XCTAssertEqual(reportedRange, NSRange(location: 2, length: 3))
    }

    func testReturnKeyPressRoutesThroughNativeView() {
        let editor = makeEditor()
        var receivedKeyPress: AppTextEditorKeyPress?
        editor.configure(ChatTextEditorConfiguration(
            text: "Send this",
            keyPressKeys: [.return],
            onKeyPress: { keyPress in
                receivedKeyPress = keyPress
                return .handled
            }
        ))

        let handled = editor.textView(
            editor.textViewForTesting,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(receivedKeyPress?.key, .return)
        XCTAssertEqual(receivedKeyPress?.modifiers, [])
    }

    func testCommandReturnKeyEquivalentRoutesThroughNativeView() throws {
        let editor = makeEditor()
        var receivedKeyPress: AppTextEditorKeyPress?
        editor.configure(ChatTextEditorConfiguration(
            text: "Send this",
            keyPressKeys: [.return],
            onKeyPress: { keyPress in
                receivedKeyPress = keyPress
                return .handled
            }
        ))
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ))

        let handled = editor.textViewForTesting.performKeyEquivalent(with: event)

        XCTAssertTrue(handled)
        XCTAssertEqual(receivedKeyPress?.key, .return)
        XCTAssertEqual(receivedKeyPress?.modifiers, .command)
    }

    func testProgrammaticMultilineTextReportsMeasuredHeightGrowth() {
        let editor = makeEditor()
        var measuredHeights: [CGFloat] = []
        editor.configure(ChatTextEditorConfiguration(
            text: "One",
            onMeasuredHeightChange: { measuredHeights.append($0) }
        ))
        flushMainQueue()

        editor.configure(ChatTextEditorConfiguration(
            text: "One\nTwo\nThree",
            onMeasuredHeightChange: { measuredHeights.append($0) }
        ))
        flushMainQueue()

        XCTAssertGreaterThan(measuredHeights.last ?? 0, measuredHeights.first ?? 0)
    }

    func testProgrammaticMultilineTextReportsMeasuredHeightShrink() {
        let editor = makeEditor()
        var measuredHeights: [CGFloat] = []
        editor.configure(ChatTextEditorConfiguration(
            text: "One\nTwo\nThree\nFour\nFive",
            onMeasuredHeightChange: { measuredHeights.append($0) }
        ))
        flushMainQueue()

        editor.configure(ChatTextEditorConfiguration(
            text: "f\nf",
            onMeasuredHeightChange: { measuredHeights.append($0) }
        ))
        flushMainQueue()

        let tallHeight = measuredHeights.first ?? 0
        let shortHeight = measuredHeights.last ?? 0
        XCTAssertLessThan(shortHeight, tallHeight)
    }

    func testConfigureDefersProgrammaticHeightMeasurementUntilAfterUpdateCycle() {
        let editor = makeEditor()
        var measuredHeights: [CGFloat] = []

        editor.configure(ChatTextEditorConfiguration(
            text: "One\nTwo",
            onMeasuredHeightChange: { measuredHeights.append($0) }
        ))

        XCTAssertTrue(measuredHeights.isEmpty)
        flushMainQueue()
        XCTAssertFalse(measuredHeights.isEmpty)
    }

    func testLayoutChangeDefersHeightMeasurementUntilAfterUpdateCycle() {
        let editor = makeEditor()
        var measuredHeights: [CGFloat] = []
        editor.configure(ChatTextEditorConfiguration(
            text: "One very long composer line that wraps differently when the editor width changes during layout.",
            onMeasuredHeightChange: { measuredHeights.append($0) }
        ))
        flushMainQueue()
        measuredHeights.removeAll()

        editor.frame.size.width = 180
        editor.needsLayout = true
        editor.layoutSubtreeIfNeeded()

        XCTAssertTrue(measuredHeights.isEmpty)
        flushMainQueue()
        XCTAssertFalse(measuredHeights.isEmpty)
    }

    func testDisabledCursorStateThreadsThroughNativeViews() {
        let editor = makeEditor()
        editor.configure(ChatTextEditorConfiguration(
            text: "",
            isDisabled: true,
            showsDisabledCursor: true
        ))

        let textView = editor.textViewForTesting
        XCTAssertFalse(textView.isEditable)
        XCTAssertFalse(textView.isSelectable)
        XCTAssertTrue(textView.showsDisabledCursor)
    }

    func testFocusRequestIsConsumedOncePerToken() {
        let editor = makeEditor()
        var consumeCount = 0
        let token = UUID()
        let configuration = ChatTextEditorConfiguration(
            text: "",
            requestFirstResponder: token,
            onFocusRequestConsumed: { consumeCount += 1 }
        )

        editor.configure(configuration)
        editor.configure(configuration)

        let expectation = XCTestExpectation(description: "focus token consumed once")
        DispatchQueue.main.async {
            XCTAssertEqual(consumeCount, 1)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testPlainFocusRequestClaimsFirstResponderWhenWindowIsAvailable() {
        let editor = makeEditor()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 96), styleMask: [], backing: .buffered, defer: false)
        window.contentView = editor

        editor.configure(ChatTextEditorConfiguration(
            text: "",
            wantsFirstResponder: true
        ))

        let expectation = XCTestExpectation(description: "plain focus claimed")
        DispatchQueue.main.async {
            XCTAssertTrue(window.firstResponder === editor.textViewForTesting)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testFocusChangesAreDedupedAcrossNativeCallbacks() {
        let editor = makeEditor()
        var reportedFocusValues: [Bool] = []
        editor.configure(ChatTextEditorConfiguration(
            text: "",
            onFocusChange: { reportedFocusValues.append($0) }
        ))

        editor.textDidBeginEditing(Notification(name: NSText.didBeginEditingNotification, object: editor.textViewForTesting))
        editor.textViewForTesting.onFocusChange?(true)
        editor.textViewForTesting.onFocusChange?(false)
        editor.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: editor.textViewForTesting))

        XCTAssertEqual(reportedFocusValues, [true, false])
    }

    func makeEditor() -> ChatTextEditorView {
        let editor = ChatTextEditorView(frame: NSRect(x: 0, y: 0, width: 420, height: 96))
        editor.layoutSubtreeIfNeeded()
        return editor
    }

    func flushMainQueue() {
        let expectation = XCTestExpectation(description: "main queue flushed")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }
}

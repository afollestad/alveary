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
        XCTAssertEqual(textView.textChipDisplayMode(for: chip), .compactLabel("@Chat%20Input.swift"))
        XCTAssertEqual(
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

        editor.configure(ChatTextEditorConfiguration(
            text: "One\nTwo\nThree",
            onMeasuredHeightChange: { measuredHeights.append($0) }
        ))

        XCTAssertGreaterThan(measuredHeights.last ?? 0, measuredHeights.first ?? 0)
    }

    func testProgrammaticMultilineTextReportsMeasuredHeightShrink() {
        let editor = makeEditor()
        var measuredHeights: [CGFloat] = []
        editor.configure(ChatTextEditorConfiguration(
            text: "One\nTwo\nThree\nFour\nFive",
            onMeasuredHeightChange: { measuredHeights.append($0) }
        ))

        editor.configure(ChatTextEditorConfiguration(
            text: "f\nf",
            onMeasuredHeightChange: { measuredHeights.append($0) }
        ))

        let tallHeight = measuredHeights.first ?? 0
        let shortHeight = measuredHeights.last ?? 0
        XCTAssertLessThan(shortHeight, tallHeight)
    }

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

    private func makeEditor() -> ChatTextEditorView {
        let editor = ChatTextEditorView(frame: NSRect(x: 0, y: 0, width: 420, height: 96))
        editor.layoutSubtreeIfNeeded()
        return editor
    }
}

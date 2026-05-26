import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
final class AppKitTextEditorCoordinatorTests: XCTestCase {

    func testHandleLayoutChangeReappliesChipVisibilityWhenMentionWraps() {
        let text = "Inspect @Alveary/Views/Chat/ChatView.swift next"
        var measuredHeight: CGFloat = 0

        let parent = AppKitTextEditorView(
            text: .constant(text),
            measuredTextHeight: Binding(get: { measuredHeight }, set: { measuredHeight = $0 }),
            placeholder: nil,
            horizontalPadding: 10,
            verticalPadding: 10,
            isDisabled: false,
            focus: nil,
            textChips: ChatComposerTextSupport.composerTextChips(in:),
            keyPressKeys: [],
            onKeyPress: nil
        )

        let coordinator = AppKitTextEditorCoordinator(parent: parent)
        let scrollView = AppKitTextEditorScrollView(frame: NSRect(x: 0, y: 0, width: 760, height: 120))
        let textView = AppKitTextView(frame: NSRect(x: 0, y: 0, width: 760, height: 120))
        textView.baseTextFont = .preferredFont(forTextStyle: .body)
        textView.font = textView.baseTextFont
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 760, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text
        scrollView.documentView = textView
        coordinator.attach(textView: textView, scrollView: scrollView)

        coordinator.applyConfiguration(from: parent)

        let mentionOffset = (text as NSString).range(of: "@Alveary/Views/Chat/ChatView.swift").location + 1
        guard let initialColor = textView.textStorage?.attribute(.foregroundColor, at: mentionOffset, effectiveRange: nil) as? NSColor else {
            return XCTFail("Expected mention styling")
        }

        XCTAssertEqual(initialColor, NSColor.clear)

        scrollView.frame.size.width = 180
        textView.textContainer?.containerSize = NSSize(width: 180, height: CGFloat.greatestFiniteMagnitude)
        coordinator.handleLayoutChange()

        guard let wrappedColor = textView.textStorage?.attribute(.foregroundColor, at: mentionOffset, effectiveRange: nil) as? NSColor else {
            return XCTFail("Expected wrapped mention styling")
        }

        XCTAssertEqual(wrappedColor, AppMarkdownCodeBlockPalette.composerChipForegroundNSColor)
    }

    func testSyncFocusRequestIfNeededFiresConsumedCallbackForNewToken() {
        let expectation = XCTestExpectation(description: "onFocusRequestConsumed fires")
        expectation.expectedFulfillmentCount = 1
        expectation.assertForOverFulfill = true

        let coordinator = makeCoordinatorForFocusRequest(
            token: UUID(),
            onConsumed: { expectation.fulfill() }
        )

        coordinator.syncFocusRequestIfNeeded()

        wait(for: [expectation], timeout: 1.0)
    }

    func testSyncFocusRequestIfNeededIgnoresRepeatedSameToken() {
        let expectation = XCTestExpectation(description: "onFocusRequestConsumed fires once for repeated tokens")
        expectation.expectedFulfillmentCount = 1
        expectation.assertForOverFulfill = true

        let token = UUID()
        let coordinator = makeCoordinatorForFocusRequest(
            token: token,
            onConsumed: { expectation.fulfill() }
        )

        coordinator.syncFocusRequestIfNeeded()
        coordinator.syncFocusRequestIfNeeded()
        coordinator.syncFocusRequestIfNeeded()

        wait(for: [expectation], timeout: 1.0)
    }

    func testSyncFocusRequestIfNeededIgnoresNilToken() {
        let expectation = XCTestExpectation(description: "onFocusRequestConsumed does not fire for nil token")
        expectation.isInverted = true

        let coordinator = makeCoordinatorForFocusRequest(
            token: nil,
            onConsumed: { expectation.fulfill() }
        )

        coordinator.syncFocusRequestIfNeeded()

        wait(for: [expectation], timeout: 0.2)
    }

    func testSyncSelectionIfNeededNormalizesStaleSelectionAfterTextReset() {
        var text = ""
        let staleText = "hello"
        var selection: TextSelection? = TextSelection(
            insertionPoint: staleText.index(staleText.startIndex, offsetBy: 3)
        )
        var measuredHeight: CGFloat = 0

        let parent = AppKitTextEditorView(
            text: Binding(get: { text }, set: { text = $0 }),
            selection: Binding(get: { selection }, set: { selection = $0 }),
            measuredTextHeight: Binding(get: { measuredHeight }, set: { measuredHeight = $0 }),
            placeholder: nil,
            horizontalPadding: 10,
            verticalPadding: 10,
            isDisabled: false,
            focus: nil,
            textHighlightRanges: nil,
            inlineHint: nil,
            keyPressKeys: [],
            onKeyPress: nil
        )

        let coordinator = AppKitTextEditorCoordinator(parent: parent)
        let textView = AppKitTextView(frame: .zero)
        textView.string = text
        let scrollView = AppKitTextEditorScrollView(frame: .zero)
        scrollView.documentView = textView
        coordinator.attach(textView: textView, scrollView: scrollView)

        coordinator.syncSelectionIfNeeded()

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
    }

    func testSyncTextIfNeededRecalculatesHeightForProgrammaticMultilineText() async throws {
        var text = ""
        var measuredHeight: CGFloat = 0
        let measuredHeightBinding = Binding(get: { measuredHeight }, set: { measuredHeight = $0 })
        let textBinding = Binding(get: { text }, set: { text = $0 })
        let parent = AppKitTextEditorView(
            text: textBinding,
            measuredTextHeight: measuredHeightBinding,
            placeholder: nil,
            horizontalPadding: 10,
            verticalPadding: 10,
            isDisabled: false,
            focus: nil,
            keyPressKeys: [],
            onKeyPress: nil
        )
        let coordinator = AppKitTextEditorCoordinator(parent: parent)
        let scrollView = AppKitTextEditorScrollView(frame: NSRect(x: 0, y: 0, width: 240, height: 40))
        let textView = AppKitTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 40))
        textView.baseTextFont = .preferredFont(forTextStyle: .body)
        textView.font = textView.baseTextFont
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        scrollView.documentView = textView
        coordinator.attach(textView: textView, scrollView: scrollView)
        coordinator.recalculateHeight()
        let initialHeight = measuredHeight

        text = "Primary goal:\n- Test session handoff.\n\nCurrent state:\n- Generated context should fit."
        coordinator.parent = parent
        coordinator.syncTextIfNeeded()
        coordinator.recalculateHeight()
        await Task.yield()

        XCTAssertEqual(textView.string, text)
        XCTAssertGreaterThan(measuredHeight, initialHeight + 20)
        XCTAssertGreaterThan(textView.textContainer?.containerSize.width ?? 0, 0)
        let multilineHeight = measuredHeight

        text = ""
        coordinator.parent = parent
        coordinator.syncTextIfNeeded()
        coordinator.recalculateHeight()
        await Task.yield()

        XCTAssertEqual(textView.string, "")
        XCTAssertLessThan(measuredHeight, multilineHeight - 20)
    }

    func testApplyConfigurationThreadsDisabledCursorStateThroughEditorViews() {
        var measuredHeight: CGFloat = 0
        let parent = AppKitTextEditorView(
            text: .constant(""),
            measuredTextHeight: Binding(get: { measuredHeight }, set: { measuredHeight = $0 }),
            placeholder: nil,
            horizontalPadding: 10,
            verticalPadding: 10,
            isDisabled: true,
            showsDisabledCursor: true,
            focus: nil,
            keyPressKeys: [],
            onKeyPress: nil
        )
        let coordinator = AppKitTextEditorCoordinator(parent: parent)
        let containerView = AppKitTextEditorContainerView(frame: .zero)
        let scrollView = AppKitTextEditorScrollView(frame: .zero)
        let clipView = AppKitTextEditorClipView(frame: .zero)
        let textView = AppKitTextView(frame: .zero)

        scrollView.contentView = clipView
        scrollView.documentView = textView
        coordinator.attach(containerView: containerView, textView: textView, scrollView: scrollView)
        coordinator.applyConfiguration(from: parent)

        XCTAssertFalse(textView.isEditable)
        XCTAssertFalse(textView.isSelectable)
        XCTAssertTrue(textView.showsDisabledCursor)
        XCTAssertTrue(scrollView.showsDisabledCursor)
        XCTAssertTrue(clipView.showsDisabledCursor)
        XCTAssertTrue(containerView.showsDisabledCursor)
    }

    func testDoCommandMapsCommandReturnSelectorToReturnKeyPress() {
        var handledKeyPress: AppTextEditorKeyPress?
        var measuredHeight: CGFloat = 0
        let parent = AppKitTextEditorView(
            text: .constant(""),
            measuredTextHeight: Binding(get: { measuredHeight }, set: { measuredHeight = $0 }),
            placeholder: nil,
            horizontalPadding: 10,
            verticalPadding: 10,
            isDisabled: false,
            focus: nil,
            keyPressKeys: [.return],
            onKeyPress: { keyPress in
                handledKeyPress = keyPress
                return .handled
            }
        )
        let coordinator = AppKitTextEditorCoordinator(parent: parent)
        let textView = AppKitTextView(frame: .zero)
        let scrollView = AppKitTextEditorScrollView(frame: .zero)
        scrollView.documentView = textView
        coordinator.attach(textView: textView, scrollView: scrollView)

        let handled = coordinator.textView(
            textView,
            doCommandBy: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(handledKeyPress?.key, .return)
    }

    func testTextViewKeyEquivalentMapsCommandReturnToReturnKeyPress() throws {
        var handledKeyPress: AppTextEditorKeyPress?
        var measuredHeight: CGFloat = 0
        let parent = AppKitTextEditorView(
            text: .constant(""),
            measuredTextHeight: Binding(get: { measuredHeight }, set: { measuredHeight = $0 }),
            placeholder: nil,
            horizontalPadding: 10,
            verticalPadding: 10,
            isDisabled: false,
            focus: nil,
            keyPressKeys: [.return],
            onKeyPress: { keyPress in
                handledKeyPress = keyPress
                return .handled
            }
        )
        let coordinator = AppKitTextEditorCoordinator(parent: parent)
        let textView = AppKitTextView(frame: .zero)
        textView.onKeyEquivalent = { event in
            coordinator.handleKeyEquivalent(event)
        }
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

        let handled = textView.performKeyEquivalent(with: event)

        XCTAssertTrue(handled)
        XCTAssertEqual(handledKeyPress?.key, .return)
        XCTAssertEqual(handledKeyPress?.modifiers, .command)
    }

    private func makeCoordinatorForFocusRequest(
        token: UUID?,
        onConsumed: @escaping () -> Void
    ) -> AppKitTextEditorCoordinator {
        var measuredHeight: CGFloat = 0

        let parent = AppKitTextEditorView(
            text: .constant(""),
            measuredTextHeight: Binding(get: { measuredHeight }, set: { measuredHeight = $0 }),
            placeholder: nil,
            horizontalPadding: 10,
            verticalPadding: 10,
            isDisabled: false,
            focus: nil,
            keyPressKeys: [],
            onKeyPress: nil,
            requestFirstResponder: token,
            onFocusRequestConsumed: onConsumed
        )

        let coordinator = AppKitTextEditorCoordinator(parent: parent)
        let textView = AppKitTextView(frame: .zero)
        let scrollView = AppKitTextEditorScrollView(frame: .zero)
        scrollView.documentView = textView
        coordinator.attach(textView: textView, scrollView: scrollView)
        return coordinator
    }
}

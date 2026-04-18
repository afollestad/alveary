import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
final class AppKitTextEditorCoordinatorTests: XCTestCase {

    func testHandleLayoutChangeReappliesChipVisibilityWhenMentionWraps() {
        let text = "Inspect @Alveary/Views/Input/ChatInputField.swift next"
        var measuredHeight: CGFloat = 0

        let parent = AppKitTextEditorView(
            text: .constant(text),
            measuredTextHeight: Binding(get: { measuredHeight }, set: { measuredHeight = $0 }),
            placeholder: nil,
            horizontalPadding: 10,
            verticalPadding: 10,
            isDisabled: false,
            focus: nil,
            textChips: { ChatInputFieldTextSupport.composerTextChips(in: $0, workingDirectory: nil) },
            keyPressKeys: [],
            onKeyPress: nil
        )

        let coordinator = AppKitTextEditorCoordinator(parent: parent)
        let scrollView = AppKitTextEditorScrollView(frame: NSRect(x: 0, y: 0, width: 760, height: 120))
        let textView = AppKitTextView(frame: NSRect(x: 0, y: 0, width: 760, height: 120))
        textView.baseTextFont = .preferredFont(forTextStyle: .body)
        textView.font = textView.baseTextFont
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 760, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text
        scrollView.documentView = textView
        coordinator.attach(textView: textView, scrollView: scrollView)

        coordinator.applyConfiguration(from: parent)

        guard let mentionRange = text.range(of: "@Alveary/Views/Input/ChatInputField.swift") else {
            return XCTFail("Expected mention range")
        }

        let hiddenPrefixIndex = text.index(mentionRange.lowerBound, offsetBy: 1)
        guard let mentionOffset = ChatInputFieldTextSupport.offset(of: hiddenPrefixIndex, in: text),
              let initialColor = textView.textStorage?.attribute(.foregroundColor, at: mentionOffset, effectiveRange: nil) as? NSColor else {
            return XCTFail("Expected mention styling")
        }

        XCTAssertEqual(initialColor, .clear)

        scrollView.frame.size.width = 180
        textView.textContainer?.containerSize = NSSize(width: 180, height: CGFloat.greatestFiniteMagnitude)
        coordinator.handleLayoutChange()

        guard let wrappedColor = textView.textStorage?.attribute(.foregroundColor, at: mentionOffset, effectiveRange: nil) as? NSColor else {
            return XCTFail("Expected wrapped mention styling")
        }

        XCTAssertEqual(wrappedColor, AppMarkdownCodeBlockPalette.inlineForegroundNSColor)
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

        XCTAssertEqual(
            ChatInputFieldTextSupport.insertionPointOffset(text: text, textSelection: selection),
            0
        )
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
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

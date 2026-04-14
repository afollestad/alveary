import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
final class AppKitTextEditorCoordinatorTests: XCTestCase {
    func testActiveCompletionTokenReturnsNilForStaleSelectionAfterTextReset() {
        let staleText = "@file"
        let staleSelection = TextSelection(
            insertionPoint: staleText.index(staleText.startIndex, offsetBy: staleText.count)
        )

        let token = ChatInputFieldTextSupport.activeCompletionToken(
            text: "",
            textSelection: staleSelection
        )

        XCTAssertNil(token)
    }

    func testEditableSelectionOffsetsReturnNilForStaleSelectionAfterTextReset() {
        let staleText = "@file"
        let staleSelection = TextSelection(
            range: staleText.startIndex..<staleText.endIndex
        )

        let offsets = ChatInputFieldTextSupport.editableSelectionOffsets(
            text: "",
            textSelection: staleSelection
        )

        XCTAssertNil(offsets)
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
}

import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension AppKitTextEditorCoordinatorTests {
    func testPlainAppTextEditorDoesNotTreatBackticksAsHiddenCodeBlockChrome() {
        var text = "```\nlet value = 1"
        var measuredHeight: CGFloat = 0
        let parent = AppKitTextEditorView(
            text: Binding(get: { text }, set: { text = $0 }),
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
        let scrollView = AppKitTextEditorScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        let textView = AppKitTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        textView.baseTextFont = .preferredFont(forTextStyle: .body)
        textView.font = textView.baseTextFont
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text
        scrollView.documentView = textView
        coordinator.attach(textView: textView, scrollView: scrollView)

        coordinator.applyConfiguration(from: parent)

        XCTAssertFalse(textView.enablesCodeBlockEditing)
        XCTAssertTrue(textView.codeBlockBackgroundRanges.isEmpty)
        XCTAssertTrue(textView.hiddenCodeBlockDelimiterRects().isEmpty)
        XCTAssertNotEqual(textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .clear)

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.insertText("```", replacementRange: NSRange(location: NSNotFound, length: 0))

        XCTAssertEqual(textView.string, "``````\nlet value = 1")
    }
}

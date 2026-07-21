import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension AppKitTextEditorCoordinatorTests {
    func testApplyConfigurationSkipsRestylingForIdenticalDerivedPresentation() throws {
        let text = "Plain text"
        var measuredHeight: CGFloat = 0
        let parent = AppKitTextEditorView(
            text: .constant(text),
            measuredTextHeight: Binding(get: { measuredHeight }, set: { measuredHeight = $0 }),
            placeholder: "Instructions",
            horizontalPadding: 10,
            verticalPadding: 10,
            isDisabled: false,
            focus: nil,
            keyPressKeys: [],
            onKeyPress: nil
        )
        let coordinator = AppKitTextEditorCoordinator(parent: parent)
        let scrollView = AppKitTextEditorScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 120))
        let textView = makeResizePerformanceTextView(text: text, width: 400)
        scrollView.documentView = textView
        coordinator.attach(textView: textView, scrollView: scrollView)
        coordinator.applyConfiguration(from: parent)

        let sentinel = NSAttributedString.Key("AppKitTextEditorCoordinatorTests.sentinel")
        textView.textStorage?.addAttribute(sentinel, value: true, range: NSRange(location: 0, length: 1))

        coordinator.applyConfiguration(from: parent)

        XCTAssertEqual(try XCTUnwrap(textView.textStorage?.attribute(sentinel, at: 0, effectiveRange: nil) as? Bool), true)
    }

    func testWidthOnlyPlainTextLayoutRecalculatesHeightWithoutRestyling() throws {
        let text = String(repeating: "Resize plain text without rebuilding its attributed presentation. ", count: 8)
        var measuredHeight: CGFloat = 0
        let parent = AppKitTextEditorView(
            text: .constant(text),
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
        let scrollView = AppKitTextEditorScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 120))
        let textView = makeResizePerformanceTextView(text: text, width: 640)
        scrollView.documentView = textView
        coordinator.attach(textView: textView, scrollView: scrollView)
        coordinator.applyConfiguration(from: parent)
        coordinator.handleLayoutChange()
        let wideHeight = measuredHeight

        let sentinel = NSAttributedString.Key("AppKitTextEditorCoordinatorTests.widthSentinel")
        textView.textStorage?.addAttribute(sentinel, value: true, range: NSRange(location: 0, length: 1))
        scrollView.frame.size.width = 180
        coordinator.handleLayoutChange()

        XCTAssertGreaterThan(measuredHeight, wideHeight)
        XCTAssertEqual(try XCTUnwrap(textView.textStorage?.attribute(sentinel, at: 0, effectiveRange: nil) as? Bool), true)
    }

    func testFixedHeightEditorDoesNotPublishMeasuredHeightDuringLayout() {
        let text = String(repeating: "Fixed-height editor text should wrap without publishing height. ", count: 8)
        var measuredHeight: CGFloat = 0
        var heightWriteCount = 0
        let parent = AppKitTextEditorView(
            text: .constant(text),
            measuredTextHeight: Binding(
                get: { measuredHeight },
                set: {
                    measuredHeight = $0
                    heightWriteCount += 1
                }
            ),
            reportsMeasuredTextHeight: false,
            placeholder: nil,
            horizontalPadding: 10,
            verticalPadding: 10,
            isDisabled: false,
            focus: nil,
            keyPressKeys: [],
            onKeyPress: nil
        )
        let coordinator = AppKitTextEditorCoordinator(parent: parent)
        let scrollView = AppKitTextEditorScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 120))
        let textView = makeResizePerformanceTextView(text: text, width: 640)
        scrollView.documentView = textView
        coordinator.attach(textView: textView, scrollView: scrollView)

        coordinator.handleLayoutChange()
        scrollView.frame.size.width = 180
        coordinator.handleLayoutChange()

        XCTAssertEqual(heightWriteCount, 0)
    }

    func testInsetChangeRestylesChipPresentation() throws {
        let text = "Inspect @Alveary/App/ContentView.swift"
        var measuredHeight: CGFloat = 0
        var parent = AppKitTextEditorView(
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
        let scrollView = AppKitTextEditorScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 120))
        let textView = makeResizePerformanceTextView(text: text, width: 400)
        scrollView.documentView = textView
        coordinator.attach(textView: textView, scrollView: scrollView)
        coordinator.applyConfiguration(from: parent)

        let sentinel = NSAttributedString.Key("AppKitTextEditorCoordinatorTests.insetSentinel")
        textView.textStorage?.addAttribute(sentinel, value: true, range: NSRange(location: 0, length: 1))
        parent = AppKitTextEditorView(
            text: .constant(text),
            measuredTextHeight: Binding(get: { measuredHeight }, set: { measuredHeight = $0 }),
            placeholder: nil,
            horizontalPadding: 20,
            verticalPadding: 10,
            isDisabled: false,
            focus: nil,
            textChips: ChatComposerTextSupport.composerTextChips(in:),
            keyPressKeys: [],
            onKeyPress: nil
        )

        coordinator.applyConfiguration(from: parent)

        XCTAssertNil(textView.textStorage?.attribute(sentinel, at: 0, effectiveRange: nil))
        XCTAssertEqual(textView.textContainerInset.width, 20)
    }

    private func makeResizePerformanceTextView(text: String, width: CGFloat) -> AppKitTextView {
        let textView = AppKitTextView(frame: NSRect(x: 0, y: 0, width: width, height: 120))
        textView.baseTextFont = .preferredFont(forTextStyle: .body)
        textView.font = textView.baseTextFont
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text
        return textView
    }
}

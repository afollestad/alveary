import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension AppKitTextEditorCoordinatorTests {
    func testSelectionChangeRestylesChipAsynchronously() {
        let chip = AppTextEditorChip(
            range: NSRange(location: 8, length: 41),
            displayText: "@ChatView.swift",
            style: .fileMention
        )
        let harness = makeSelectionRestyleHarness(chip: chip)
        let chipInteriorOffset = chip.range.location + 1

        let initialColor = harness.textView.textStorage?.attribute(
            .foregroundColor,
            at: chipInteriorOffset,
            effectiveRange: nil
        ) as? NSColor
        XCTAssertEqual(initialColor?.alphaComponent, 0)

        harness.textView.setSelectedRange(NSRange(location: 20, length: 0))
        harness.coordinator.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: harness.textView)
        )

        let restyled = expectation(description: "Selection restyle")
        DispatchQueue.main.async {
            restyled.fulfill()
        }
        wait(for: [restyled], timeout: 1)

        let updatedColor = harness.textView.textStorage?.attribute(
            .foregroundColor,
            at: chipInteriorOffset,
            effectiveRange: nil
        ) as? NSColor
        XCTAssertGreaterThan(updatedColor?.alphaComponent ?? 0, 0)
    }

    private func makeSelectionRestyleHarness(chip: AppTextEditorChip) -> (
        coordinator: AppKitTextEditorCoordinator,
        textView: AppKitTextView
    ) {
        var text = "Inspect @Alveary/Views/Chat/ChatView.swift next"
        var measuredHeight: CGFloat = 0
        let parent = AppKitTextEditorView(
            text: Binding(get: { text }, set: { text = $0 }),
            selection: nil,
            measuredTextHeight: Binding(get: { measuredHeight }, set: { measuredHeight = $0 }),
            placeholder: nil,
            horizontalPadding: 10,
            verticalPadding: 10,
            isDisabled: false,
            focus: nil,
            textHighlightRanges: nil,
            textChips: { _ in [chip] },
            inlineHint: nil,
            keyPressKeys: [],
            onKeyPress: nil
        )

        let coordinator = AppKitTextEditorCoordinator(parent: parent)
        let textView = AppKitTextView(frame: NSRect(x: 0, y: 0, width: 760, height: 120))
        textView.font = .preferredFont(forTextStyle: .body)
        textView.baseTextFont = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 760, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text

        let scrollView = AppKitTextEditorScrollView(frame: NSRect(x: 0, y: 0, width: 760, height: 120))
        scrollView.documentView = textView

        coordinator.attach(textView: textView, scrollView: scrollView)
        coordinator.applyConfiguration(from: parent)
        return (coordinator, textView)
    }
}

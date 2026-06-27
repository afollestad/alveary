@preconcurrency import AppKit
import SwiftUI

struct AppImagePreviewTextView: NSViewRepresentable {
    let text: String
    let accessibilityLabel: String
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        let textView = EscapeClosingTextView()
        textView.onEscape = onEscape
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.string = text
        textView.setAccessibilityLabel(accessibilityLabel)

        scrollView.documentView = textView
        applyColors(scrollView: scrollView, textView: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? EscapeClosingTextView else {
            return
        }
        textView.onEscape = onEscape
        if textView.string != text {
            textView.string = text
        }
        textView.setAccessibilityLabel(accessibilityLabel)
        applyColors(scrollView: scrollView, textView: textView)
    }

    private func applyColors(scrollView: NSScrollView, textView: NSTextView) {
        let backgroundColor = NSColor.textBackgroundColor
        scrollView.backgroundColor = backgroundColor
        textView.drawsBackground = true
        textView.backgroundColor = backgroundColor
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
    }
}

private final class EscapeClosingTextView: NSTextView {
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}

@preconcurrency import AppKit

/// Horizontal overflow container for embedded code/table surfaces inside the
/// AppKit transcript.
final class AppKitHorizontalOverflowScrollView: NSScrollView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureOverflowScroller()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureOverflowScroller()
    }

    override func scrollWheel(with event: NSEvent) {
        // Code blocks own horizontal overflow, but vertical gestures must keep
        // moving the AppKit transcript instead of being trapped inside the block.
        guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
              let ancestor = ancestorScrollView else {
            super.scrollWheel(with: event)
            return
        }
        ancestor.scrollWheel(with: event)
    }

    private var ancestorScrollView: NSScrollView? {
        var candidate = superview
        while let view = candidate {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            candidate = view.superview
        }
        return nil
    }

    private func configureOverflowScroller() {
        autohidesScrollers = true
        scrollerStyle = .overlay
    }
}

@MainActor
var appKitHorizontalOverflowScrollbarReserve: CGFloat {
    appKitHorizontalOverflowScrollbarReserveValue(for: NSScroller.preferredScrollerStyle)
}

@MainActor
func appKitHorizontalOverflowScrollbarReserveValue(for scrollerStyle: NSScroller.Style) -> CGFloat {
    // Overlay scrollers fade over content; reserving their full thickness leaves
    // a permanent gutter. Only reserve space when the system asks for legacy,
    // always-visible scrollers that otherwise consume the final line's space.
    guard scrollerStyle == .legacy else {
        return 0
    }
    return ceil(NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy))
}

func appKitCodeDisplayContent(_ content: String) -> String {
    appMarkdownCodeDisplayContent(content)
}

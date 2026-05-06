@preconcurrency import AppKit

/// Horizontal overflow container for embedded code/table surfaces inside the
/// AppKit transcript.
final class AppKitHorizontalOverflowScrollView: NSScrollView {
    private var isForwardingVerticalScrollSequence = false
    private var verticalScrollSequenceToken = UUID()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureOverflowScroller()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureOverflowScroller()
    }

    override func scrollWheel(with event: NSEvent) {
        if shouldForwardVerticalScroll(event),
           let verticalAncestorScrollView {
            isForwardingVerticalScrollSequence = true
            schedulePhaseLessVerticalScrollSequenceResetIfNeeded(for: event)
            verticalAncestorScrollView.scrollWheel(with: event)
            updateVerticalScrollSequenceState(after: event)
            return
        }
        if isForwardingVerticalScrollSequence,
           let verticalAncestorScrollView {
            verticalAncestorScrollView.scrollWheel(with: event)
            schedulePhaseLessVerticalScrollSequenceResetIfNeeded(for: event)
            updateVerticalScrollSequenceState(after: event)
            return
        }
        updateVerticalScrollSequenceState(after: event)
        super.scrollWheel(with: event)
    }

    private func shouldForwardVerticalScroll(_ event: NSEvent) -> Bool {
        let deltaY = abs(event.scrollingDeltaY)
        return deltaY > 0 && deltaY >= abs(event.scrollingDeltaX)
    }

    private func updateVerticalScrollSequenceState(after event: NSEvent) {
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) ||
            event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
            isForwardingVerticalScrollSequence = false
            verticalScrollSequenceToken = UUID()
        }
    }

    private func schedulePhaseLessVerticalScrollSequenceResetIfNeeded(for event: NSEvent) {
        guard event.phase == [], event.momentumPhase == [] else {
            return
        }
        let token = UUID()
        verticalScrollSequenceToken = token
        DispatchQueue.main.async { [weak self] in
            guard self?.verticalScrollSequenceToken == token else {
                return
            }
            self?.isForwardingVerticalScrollSequence = false
        }
    }

    private var verticalAncestorScrollView: NSScrollView? {
        var candidate = superview
        while let view = candidate {
            if let scrollView = view as? NSScrollView,
               scrollView.hasVerticalScroller {
                return scrollView
            }
            candidate = view.superview
        }
        return nil
    }

    private func configureOverflowScroller() {
        autohidesScrollers = true
        scrollerStyle = .overlay
        verticalScrollElasticity = .none
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

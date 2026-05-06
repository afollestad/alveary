import AppKit

/// Invisible hit target layered above the surface-hoisted autocomplete popup.
///
/// The popup itself is reused from the composer body, but the surface needs a
/// concrete topmost sibling view so AppKit delivers mouse and wheel events to
/// the full floating popup rect instead of to transcript content underneath it.
@MainActor
final class AutocompleteSurfaceEventCaptureView: NSView {
    private weak var popup: AppKitComposerAutocompletePopupView?

    override var isFlipped: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    func configure(popup: AppKitComposerAutocompletePopupView) {
        self.popup = popup
    }

    override func mouseMoved(with event: NSEvent) {
        guard let popup else {
            return
        }
        let windowPoint = surfaceMouseEventWindowPoint(event)
        _ = popup.routeMouseMoved(at: popup.convert(windowPoint, from: nil), event: event)
    }

    override func mouseDown(with event: NSEvent) {
        guard let popup else {
            return
        }
        let windowPoint = surfaceMouseEventWindowPoint(event)
        _ = popup.routeMouseDown(at: popup.convert(windowPoint, from: nil), event: event)
    }

    override func scrollWheel(with event: NSEvent) {
        if let surface = superview as? AppKitChatSurfaceView {
            if surface.consumeScrollWheelEventIfInsideComposerAutocomplete(event) == nil {
                return
            }
            surface.forwardScrollWheelOutsideComposerAutocomplete(event)
            return
        }
        guard let popup else {
            return
        }
        let windowPoint = window?.mouseLocationOutsideOfEventStream ?? event.locationInWindow
        _ = popup.routeScrollWheel(at: popup.convert(windowPoint, from: nil), event: event)
    }

    private func surfaceMouseEventWindowPoint(_ event: NSEvent) -> NSPoint {
        if let surface = superview as? AppKitChatSurfaceView {
            return surface.mouseEventWindowPoint(event)
        }
        return event.locationInWindow
    }
}

/// RAII wrapper for local AppKit event monitors.
///
/// `NSEvent.addLocalMonitorForEvents` returns an opaque token that must be
/// removed manually. Keeping the token in this wrapper ties monitor removal to
/// the surface view's normal property lifecycle.
final class ChatSurfaceLocalEventMonitor: @unchecked Sendable {
    private let monitor: Any?

    init(_ monitor: Any?) {
        self.monitor = monitor
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

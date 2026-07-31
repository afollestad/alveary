import AppKit
import SwiftUI

/// Reports right-clicks and control-clicks inside its own bounds.
///
/// SwiftUI has no secondary-click gesture, and `contextMenu` only opens a menu —
/// too late for callers that need to act on mouse-down (selecting the clicked
/// row before the menu opens) or that want something other than a menu (opening
/// a popover). Apply it as an overlay on the control that should respond.
struct SecondaryClickTarget: NSViewRepresentable {
    let onSecondaryClick: () -> Void

    func makeNSView(context: Context) -> SecondaryClickTargetView {
        let view = SecondaryClickTargetView()
        view.onSecondaryClick = onSecondaryClick
        return view
    }

    func updateNSView(_ nsView: SecondaryClickTargetView, context: Context) {
        nsView.onSecondaryClick = onSecondaryClick
    }

    static func dismantleNSView(_ nsView: SecondaryClickTargetView, coordinator: ()) {
        nsView.dismantle()
    }
}

@MainActor
final class SecondaryClickTargetView: NSView {
    var onSecondaryClick: (() -> Void)?
    private var eventMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityElement(false)
    }

    /// Never participates in hit testing: the local monitor observes every
    /// window event with its own bounds check, so this view claiming clicks
    /// would only swallow them from the control it overlays. Without this, an
    /// `.overlay` placement eats the control's left-clicks entirely.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeEventMonitor()
        } else {
            installEventMonitor()
        }
    }

    func dismantle() {
        removeEventMonitor()
    }

    private func installEventMonitor() {
        guard eventMonitor == nil else {
            return
        }
        // A local monitor rather than `rightMouseDown(with:)` so the click is
        // observed without this overlay swallowing it from the control beneath.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self else {
                return event
            }
            self.handleMouseDown(event)
            return event
        }
    }

    private func removeEventMonitor() {
        guard let eventMonitor else {
            return
        }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    private func handleMouseDown(_ event: NSEvent) {
        let isContextClick = event.type == .rightMouseDown
            || event.type == .leftMouseDown && event.modifierFlags.contains(.control)
        guard isContextClick,
              containsEvent(event) else {
            return
        }
        onSecondaryClick?()
    }

    private func containsEvent(_ event: NSEvent) -> Bool {
        guard event.window === window else {
            return false
        }
        let point = convert(event.locationInWindow, from: nil)
        return bounds.contains(point)
    }
}

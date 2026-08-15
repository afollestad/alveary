import AppKit
import SwiftUI

/// Reports right-clicks and control-clicks inside its own bounds.
///
/// SwiftUI has no secondary-click gesture, and `contextMenu` only opens a menu —
/// too late for callers that need to act on mouse-down (selecting the clicked
/// row before the menu opens) or that want something other than a menu (opening
/// a popover). Apply it as an overlay on the control that should respond.
///
/// The click point comes through in the target view's own coordinates, for callers
/// that answer differently by region. A caller that does want a menu returns one
/// from `menuProvider` — returning `nil` declines the click — and this view pops it
/// itself, because SwiftUI cannot open a `contextMenu` from an event monitor.
struct SecondaryClickTarget: NSViewRepresentable {
    let onSecondaryClick: (CGPoint) -> Void
    var menuProvider: ((CGPoint) -> NSMenu?)?

    init(
        menuProvider: ((CGPoint) -> NSMenu?)? = nil,
        onSecondaryClick: @escaping (CGPoint) -> Void = { _ in }
    ) {
        self.menuProvider = menuProvider
        self.onSecondaryClick = onSecondaryClick
    }

    func makeNSView(context: Context) -> SecondaryClickTargetView {
        let view = SecondaryClickTargetView()
        view.onSecondaryClick = onSecondaryClick
        view.menuProvider = menuProvider
        return view
    }

    func updateNSView(_ nsView: SecondaryClickTargetView, context: Context) {
        nsView.onSecondaryClick = onSecondaryClick
        nsView.menuProvider = menuProvider
    }

    static func dismantleNSView(_ nsView: SecondaryClickTargetView, coordinator: ()) {
        nsView.dismantle()
    }
}

@MainActor
final class SecondaryClickTargetView: NSView {
    var onSecondaryClick: ((CGPoint) -> Void)?
    var menuProvider: ((CGPoint) -> NSMenu?)?
    private var eventMonitor: Any?

    /// Reported points share SwiftUI's top-left origin, so a caller can compare them against
    /// geometry it measured in a SwiftUI coordinate space. An unflipped view would hand back a
    /// vertically mirrored y and silently invert every region test built on it.
    override var isFlipped: Bool { true }

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
              let point = pointInBounds(for: event) else {
            return
        }
        onSecondaryClick?(point)
        guard let menu = menuProvider?(point) else {
            return
        }
        // Deferred a turn: popping a menu runs a nested event loop, and doing that while AppKit is
        // still dispatching this `rightMouseDown` leaves the click's own handling half-finished.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else {
                return
            }
            menu.popUp(positioning: nil, at: point, in: self)
        }
    }

    private func pointInBounds(for event: NSEvent) -> CGPoint? {
        guard event.window === window else {
            return nil
        }
        let point = convert(event.locationInWindow, from: nil)
        return bounds.contains(point) ? point : nil
    }
}

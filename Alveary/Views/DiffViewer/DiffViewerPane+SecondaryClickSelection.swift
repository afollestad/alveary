import AppKit
import SwiftUI

struct DiffViewerSecondaryClickSelectionTarget: NSViewRepresentable {
    let onSecondaryClick: () -> Void

    func makeNSView(context: Context) -> DiffViewerSecondaryClickSelectionView {
        let view = DiffViewerSecondaryClickSelectionView()
        view.onSecondaryClick = onSecondaryClick
        return view
    }

    func updateNSView(_ nsView: DiffViewerSecondaryClickSelectionView, context: Context) {
        nsView.onSecondaryClick = onSecondaryClick
    }

    static func dismantleNSView(_ nsView: DiffViewerSecondaryClickSelectionView, coordinator: ()) {
        nsView.dismantle()
    }
}

@MainActor
final class DiffViewerSecondaryClickSelectionView: NSView {
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
        // SwiftUI contextMenu selection is too late for native-feeling feedback:
        // this monitor updates row selection during mouse-down before the menu opens.
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

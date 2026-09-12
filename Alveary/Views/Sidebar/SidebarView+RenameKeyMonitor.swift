import AppKit
import SwiftUI

/// Mount this over the entire List: SwiftUI's list focus proxy is a sibling of its native
/// scroll view, so ancestry alone cannot identify the sidebar's keyboard focus.
struct SidebarRenameKeyMonitor: NSViewRepresentable {
    /// Return true only when rename starts, leaving every other Return with its responder.
    let onRename: @MainActor () -> Bool

    func makeNSView(context: Context) -> SidebarRenameKeyMonitorView {
        let view = SidebarRenameKeyMonitorView()
        view.onRename = onRename
        return view
    }

    func updateNSView(_ nsView: SidebarRenameKeyMonitorView, context: Context) {
        nsView.onRename = onRename
    }

    static func dismantleNSView(_ nsView: SidebarRenameKeyMonitorView, coordinator: ()) {
        nsView.dismantle()
    }
}

@MainActor
final class SidebarRenameKeyMonitorView: NSView {
    var onRename: (() -> Bool)?

    private var eventMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityElement(false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            dismantle()
        } else {
            installEventMonitor()
        }
    }

    func dismantle() {
        guard let eventMonitor else {
            return
        }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    private func installEventMonitor() {
        guard eventMonitor == nil else {
            return
        }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.shouldHandle(event),
                  self.onRename?() == true else {
                return event
            }
            return nil
        }
    }

    private func shouldHandle(_ event: NSEvent) -> Bool {
        let shortcutModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard event.keyCode == 36 || event.keyCode == 76,
              !event.isARepeat,
              event.modifierFlags.isDisjoint(with: shortcutModifiers),
              let window,
              window.isKeyWindow,
              event.window === window,
              window.attachedSheet == nil,
              NSApp.modalWindow == nil,
              !isHiddenOrHasHiddenAncestor,
              let responder = window.firstResponder as? NSView,
              !responder.isHiddenOrHasHiddenAncestor,
              !(responder is NSText) else {
            return false
        }

        let focusView: NSView
        if let table = responder as? NSTableView,
           let scrollView = table.enclosingScrollView {
            focusView = scrollView
        } else {
            guard !(responder is NSControl) else {
                return false
            }
            focusView = responder
        }

        // Compare the actual first responder's footprint, not its common hosting ancestor:
        // that ancestor also contains the composer, and buttons have their own focus proxies.
        let monitorRect = convert(bounds, to: nil)
        let focusRect = focusView.convert(focusView.bounds, to: nil)
        guard !monitorRect.isEmpty, !focusRect.isEmpty else {
            return false
        }
        return abs(monitorRect.minX - focusRect.minX) <= 1
            && abs(monitorRect.minY - focusRect.minY) <= 1
            && abs(monitorRect.width - focusRect.width) <= 1
            && abs(monitorRect.height - focusRect.height) <= 1
    }
}

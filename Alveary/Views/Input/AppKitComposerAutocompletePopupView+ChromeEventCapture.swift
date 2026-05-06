import AppKit

/// Hit target for non-row popup chrome, including the spacing between rows.
///
/// AppKit does not consistently deliver wheel events to the popup itself when
/// it floats outside the composer hierarchy. A concrete child hit target keeps
/// row gaps from falling through to the transcript scroll view.
@MainActor
final class AutocompletePopupChromeEventCaptureView: NSView {
    private weak var popup: AppKitComposerAutocompletePopupView?

    override var isFlipped: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func configure(popup: AppKitComposerAutocompletePopupView) {
        self.popup = popup
    }

    override func mouseMoved(with event: NSEvent) {
        guard let popup,
              popup.routeMouseMoved(at: eventPopupPoint(for: event, in: popup), event: event) else {
            return
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let popup,
              popup.routeMouseDown(at: eventPopupPoint(for: event, in: popup), event: event) else {
            return
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let popup,
              popup.routeScrollWheel(at: popupPoint(for: event, in: popup), event: event) else {
            return
        }
    }

    private func popupPoint(for event: NSEvent, in popup: AppKitComposerAutocompletePopupView) -> NSPoint {
        let eventPoint = eventPopupPoint(for: event, in: popup)
        if popup.bounds.contains(eventPoint) {
            return eventPoint
        }
        return popup.convert(NSPoint(x: bounds.midX, y: bounds.midY), from: self)
    }

    private func eventPopupPoint(for event: NSEvent, in popup: AppKitComposerAutocompletePopupView) -> NSPoint {
        popup.convert(event.locationInWindow, from: nil)
    }
}

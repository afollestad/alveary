import AppKit

/// A pressable bubble that also joins the key-view loop: Tab reaches it, Return or Space presses it,
/// and the focus ring shows only for keyboard focus. Shared by the card's reviewer rows and the
/// transcript's reviewer messages so either keeps the keyboard path to that reviewer's details.
@MainActor
class AppKitKeyboardFocusableBubbleView: AppKitHostToolWidgetBubbleView {
    enum FocusPresentation {
        case mouse, keyboard
    }

    /// Direct restoration after a sheet or rebuild must retain the opening interaction;
    /// Escape dismissing mouse-opened details is not keyboard navigation into this view.
    var focusPresentation: FocusPresentation = .mouse {
        didSet {
            guard focusPresentation != oldValue else { return }
            noteFocusRingMaskChanged()
            needsDisplay = true
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        if let direction = window?.keyViewSelectionDirection, direction != .directSelection {
            focusPresentation = .keyboard
        }
        return true
    }

    override func mouseDown(with event: NSEvent) {
        focusPresentation = .mouse
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        focusPresentation = .keyboard
        guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 36, 49, 76:
            onActivate?()
        case 48:
            // NSView does not interpret Tab for a custom control; keep the native key-view
            // loop reachable so keyboard focus can leave this view.
            if event.modifierFlags.contains(.shift) {
                window?.selectKeyView(preceding: self)
            } else {
                window?.selectKeyView(following: self)
            }
        default:
            super.keyDown(with: event)
        }
    }

    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        guard focusPresentation == .keyboard else { return }
        NSBezierPath(roundedRect: bounds, xRadius: AppCornerRadius.standard, yRadius: AppCornerRadius.standard).fill()
    }
}

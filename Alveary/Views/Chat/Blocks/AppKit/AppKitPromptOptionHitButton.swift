@preconcurrency import AppKit
import QuartzCore

/// Transparent AppKit button used to give prompt answer rows a full-width hit
/// target while leaving the selected `Other` text field above it for editing.
@MainActor
final class AppKitPromptOptionHitButton: NSButton {
    var onPressedChanged: ((Bool) -> Void)?
    var onReleased: ((Bool) -> Void)?

    override var acceptsFirstResponder: Bool {
        false
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        updatePressed(true)
        sendAction(action, to: target)
        let releasedInside = trackPressedStateUntilMouseUp()
        updatePressed(false)
        onReleased?(releasedInside)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, isEnabled, alphaValue > 0, bounds.contains(point) else {
            return nil
        }
        return self
    }

    override func draw(_ dirtyRect: NSRect) {}

    private func setup() {
        title = ""
        isBordered = false
        setButtonType(.momentaryChange)
    }

    private func updatePressed(_ pressed: Bool) {
        onPressedChanged?(pressed)
        // Mouse tracking blocks the normal run-loop presentation pass, so commit
        // the host row's layer-only pressed state without forcing window layout.
        CATransaction.flush()
    }

    private func trackPressedStateUntilMouseUp() -> Bool {
        var isInside = true
        while let event = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let point = convert(event.locationInWindow, from: nil)
            isInside = bounds.contains(point)
            if event.type == .leftMouseUp {
                return isInside
            }
            updatePressed(isInside)
        }
        return false
    }
}

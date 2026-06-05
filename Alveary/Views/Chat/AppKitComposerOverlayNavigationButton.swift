@preconcurrency import AppKit

@MainActor
final class AppKitComposerOverlayNavigationButton: NSButton {
    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else {
            return false
        }
        sendAction(action, to: target)
        return true
    }
}

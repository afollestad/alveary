import AppKit
import SwiftUI

/// Renders a SwiftUI `KeyboardShortcut` as the key equivalent an `NSMenuItem` displays.
///
/// Status-item menus do not participate in key-equivalent matching, so these are labels only —
/// the bindings themselves stay owned by `AlvearyApp.commands`. Deriving them from the same
/// `KeyboardShortcut` constants keeps the label from drifting off the active binding, the rule
/// `Alveary/App/AGENTS.md` states for tooltips.
enum MenuBarKeyEquivalent {
    static func apply(_ shortcut: KeyboardShortcut, to item: NSMenuItem) {
        item.keyEquivalent = String(shortcut.key.character).lowercased()
        item.keyEquivalentModifierMask = modifierFlags(shortcut.modifiers)
    }

    static func modifierFlags(_ modifiers: EventModifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) {
            flags.insert(.control)
        }
        if modifiers.contains(.option) {
            flags.insert(.option)
        }
        if modifiers.contains(.shift) {
            flags.insert(.shift)
        }
        if modifiers.contains(.command) {
            flags.insert(.command)
        }
        return flags
    }
}

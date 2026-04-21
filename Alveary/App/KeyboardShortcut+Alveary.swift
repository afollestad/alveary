import SwiftUI

/// App-scoped `KeyboardShortcut` definitions and tooltip rendering helpers.
///
/// Define modifier-key shortcuts here once, register them on a menu entry via
/// `CommandGroup(...)` in `AlvearyApp.commands`, and reference the same binding
/// from any matching toolbar button. See `Alveary/App/AGENTS.md` for the full
/// convention and the "Focus And Keyboard Coordination" section of
/// `Alveary/Views/AGENTS.md` for why menu registration is the right surface.
extension KeyboardShortcut {
    static let toggleDiffViewer = KeyboardShortcut("d", modifiers: [.shift, .command])

    /// Human-readable rendering, e.g. "⇧⌘D" or "⌘↩". Drives tooltip text so it
    /// stays in sync with the bound `KeyEquivalent` + `EventModifiers` without
    /// a hand-written literal.
    var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        result += key.displaySymbol
        return result
    }
}

private extension KeyEquivalent {
    /// Conventional macOS menu-bar glyph for the key. Covers the special keys
    /// SwiftUI exposes as static constants; falls back to the uppercased
    /// character for letters and digits.
    var displaySymbol: String {
        switch self {
        case .return: "↩"
        case .escape: "⎋"
        case .tab: "⇥"
        case .space: "␣"
        case .delete: "⌫"
        case .deleteForward: "⌦"
        case .upArrow: "↑"
        case .downArrow: "↓"
        case .leftArrow: "←"
        case .rightArrow: "→"
        case .home: "↖"
        case .end: "↘"
        case .pageUp: "⇞"
        case .pageDown: "⇟"
        case .clear: "⌧"
        default: String(character).uppercased()
        }
    }
}

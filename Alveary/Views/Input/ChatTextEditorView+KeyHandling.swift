@preconcurrency import AppKit
import SwiftUI

extension AppTextEditorKey {
    init?(chatTextEditorSelector selector: Selector) {
        switch selector {
        case #selector(NSResponder.moveUp(_:)):
            self = .upArrow
        case #selector(NSResponder.moveDown(_:)):
            self = .downArrow
        case #selector(NSResponder.insertTab(_:)):
            self = .tab
        case #selector(NSResponder.cancelOperation(_:)):
            self = .escape
        case #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            self = .return
        default:
            return nil
        }
    }

    init?(chatTextEditorKeyEquivalentEvent event: NSEvent) {
        guard event.type == .keyDown,
              event.modifierFlags.chatTextEditorEventModifiers.contains(.command),
              let characters = event.charactersIgnoringModifiers else {
            return nil
        }

        switch characters {
        case "\r", "\n":
            self = .return
        default:
            return nil
        }
    }
}

extension NSEvent.ModifierFlags {
    var chatTextEditorEventModifiers: EventModifiers {
        var modifiers: EventModifiers = []

        if contains(.shift) {
            modifiers.insert(.shift)
        }
        if contains(.control) {
            modifiers.insert(.control)
        }
        if contains(.option) {
            modifiers.insert(.option)
        }
        if contains(.command) {
            modifiers.insert(.command)
        }
        if contains(.capsLock) {
            modifiers.insert(.capsLock)
        }
        if contains(.numericPad) {
            modifiers.insert(.numericPad)
        }

        return modifiers
    }
}

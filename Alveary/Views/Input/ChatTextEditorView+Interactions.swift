@preconcurrency import AppKit
import SwiftUI

@MainActor
extension ChatTextEditorView {
    func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        guard let key = AppTextEditorKey(chatTextEditorKeyEquivalentEvent: event) else {
            return false
        }

        return handleKeyPress(key: key, modifiers: event.modifierFlags.chatTextEditorEventModifiers)
    }

    func handleKeyPress(key: AppTextEditorKey, modifiers: EventModifiers) -> Bool {
        guard configuration.keyPressKeys.contains(key) else {
            return false
        }

        let result = configuration.onKeyPress(AppTextEditorKeyPress(key: key, modifiers: modifiers))
        return result == .handled
    }
}

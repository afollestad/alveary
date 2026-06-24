@preconcurrency import AppKit

extension AppKitComposerOverlayPanelView {
    @discardableResult
    // swiftlint:disable:next cyclomatic_complexity
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let configuration else {
            return false
        }
        switch event.specialKey {
        case .leftArrow:
            if configuration.canNavigateBackward {
                configuration.onNavigateBackward()
            }
            return true
        case .rightArrow:
            if configuration.canNavigateForward {
                configuration.onNavigateForward()
            }
            return true
        case .upArrow:
            focusAdjacentRow(delta: -1)
            return true
        case .downArrow:
            focusAdjacentRow(delta: 1)
            return true
        case .carriageReturn:
            return handleReturnKey(configuration: configuration)
        default:
            break
        }
        if event.keyCode == 48 {
            focusAdjacentKeyView(delta: event.modifierFlags.contains(.shift) ? -1 : 1)
            return true
        }
        if event.keyCode == 53 {
            configuration.onDismiss()
            return true
        }
        if event.charactersIgnoringModifiers == " ",
           let row = focusedOrConfiguredRow {
            row.performSelectionFromKeyboard()
            return true
        }
        return false
    }

    private func handleReturnKey(configuration: Configuration) -> Bool {
        if let row = focusedOrConfiguredRow,
           shouldReturnSelectFocusedRow(row) {
            if configuration.prefersPrimaryActionForReturn,
               configuration.isPrimaryEnabled,
               !configuration.isResolving {
                configuration.onPrimary()
                return true
            }
            row.performSubmitSelection()
            return true
        }
        guard configuration.isPrimaryEnabled, !configuration.isResolving else {
            return true
        }
        configuration.onPrimary()
        return true
    }
}

import AppKit

extension ComposerReasoningMenuViewController {
    @discardableResult
    func focusEffortControl() -> Bool {
        loadViewIfNeeded()
        guard let window = view.window else {
            return false
        }
        guard let focusControl = (view as? ComposerReasoningMenuView)?.preferredEffortFocusControl else {
            window.initialFirstResponder = nil
            return window.makeFirstResponder(nil)
        }
        window.initialFirstResponder = focusControl
        return window.makeFirstResponder(focusControl)
    }
}

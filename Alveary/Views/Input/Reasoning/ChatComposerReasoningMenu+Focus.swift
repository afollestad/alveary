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

    /// Expands the models disclosure and focuses it, so `/model` lands in the list the way `/effort`
    /// lands on the effort slider. Expansion has to come first because rows are built lazily.
    @discardableResult
    func focusModelList() -> Bool {
        loadViewIfNeeded()
        setModelsExpanded(true, animated: false)
        guard let window = view.window else {
            return false
        }
        guard let focusControl = (view as? ComposerReasoningMenuView)?.preferredModelFocusControl else {
            window.initialFirstResponder = nil
            return window.makeFirstResponder(nil)
        }
        window.initialFirstResponder = focusControl
        return window.makeFirstResponder(focusControl)
    }
}

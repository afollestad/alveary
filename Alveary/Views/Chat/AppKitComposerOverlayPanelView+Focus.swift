@preconcurrency import AppKit

extension AppKitComposerOverlayPanelView {
    func focusAdjacentRow(delta: Int) {
        guard !rowViews.isEmpty else {
            return
        }
        let current = focusedOrConfiguredRow.flatMap { focused in rowViews.firstIndex { $0 === focused } } ?? -1
        let next = min(max(current + delta, 0), rowViews.count - 1)
        rowViews[next].focusPreferredTarget()
    }

    func focusAdjacentKeyView(delta: Int) {
        let keyViews = focusableKeyViews
        guard !keyViews.isEmpty else {
            return
        }
        let current = focusedKeyViewIndex(in: keyViews) ?? (delta > 0 ? -1 : 0)
        let next = (current + delta + keyViews.count) % keyViews.count
        focusKeyView(keyViews[next])
    }

    var focusableKeyViews: [NSView] {
        let rowKeyViews = rowViews.flatMap(\.keyViewSequence)
        let controls = [previousButton, nextButton, dismissButton, primaryButton].filter { !$0.isHidden && $0.isEnabled }
        return rowKeyViews + controls
    }

    var focusedOrConfiguredRow: AppKitComposerOverlayOptionRowView? {
        focusedRow ?? rowViews.first(where: \.configurationIsFocused)
    }

    func shouldReturnSelectFocusedRow(_ row: AppKitComposerOverlayOptionRowView) -> Bool {
        guard let firstResponder = window?.firstResponder as? NSView else {
            return row.configurationIsFocused
        }
        if firstResponder === row {
            return true
        }
        if firstResponder.isDescendant(of: row) {
            return false
        }
        if focusableControls.contains(where: { firstResponder === $0 || firstResponder.isDescendant(of: $0) }) {
            return false
        }
        return row.configurationIsFocused
    }

    var containsInteractiveKeyboardFocus: Bool {
        guard let firstResponder = window?.firstResponder else {
            return false
        }
        return rowViews.contains(where: \.containsKeyboardFocus) ||
            focusableKeyViews.contains {
                firstResponder === $0 ||
                    (firstResponder as? NSView)?.isDescendant(of: $0) == true
            }
    }

    private func focusedKeyViewIndex(in keyViews: [NSView]) -> Int? {
        guard let firstResponder = window?.firstResponder else {
            return keyViews.firstIndex { ($0 as? AppKitComposerOverlayOptionRowView)?.configurationIsFocused == true }
        }
        if let exact = keyViews.firstIndex(where: { firstResponder === $0 }) {
            return exact
        }
        if let descendant = keyViews.firstIndex(where: { (firstResponder as? NSView)?.isDescendant(of: $0) == true }) {
            return descendant
        }
        return keyViews.firstIndex { ($0 as? AppKitComposerOverlayOptionRowView)?.configurationIsFocused == true }
    }

    private func focusKeyView(_ view: NSView) {
        if let row = view as? AppKitComposerOverlayOptionRowView {
            row.focusPreferredTarget()
        } else {
            window?.makeFirstResponder(view)
        }
    }

    private var focusableControls: [NSView] {
        [previousButton, nextButton, dismissButton, primaryButton].filter { !$0.isHidden && $0.isEnabled }
    }

    private var focusedRow: AppKitComposerOverlayOptionRowView? {
        guard let firstResponder = window?.firstResponder else {
            return nil
        }
        return rowViews.first { row in
            row.containsKeyboardFocus ||
                firstResponder === row ||
                (firstResponder as? NSView)?.isDescendant(of: row) == true
        }
    }
}

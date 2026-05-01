@preconcurrency import AppKit
import Foundation

final class AppKitMarkdownTaskCheckbox: NSButton {
    private let id: String

    init(id: String, initialValue: Bool) {
        self.id = id
        super.init(frame: .zero)
        setButtonType(.switch)
        title = ""
        state = AppMarkdownTaskCheckboxStore.value(for: id, defaultValue: initialValue) ? .on : .off
        target = self
        action = #selector(toggle)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 16).isActive = true
        heightAnchor.constraint(equalToConstant: 16).isActive = true
        setAccessibilityIdentifier("appKitMarkdownTaskCheckbox")
        setAccessibilityLabel(state == .on ? "Completed" : "Incomplete")
        setAccessibilityValue(state == .on ? "checked" : "unchecked")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func toggle() {
        AppMarkdownTaskCheckboxStore.set(state == .on, for: id)
        setAccessibilityLabel(state == .on ? "Completed" : "Incomplete")
        setAccessibilityValue(state == .on ? "checked" : "unchecked")
    }
}

final class AppKitMarkdownRuleView: NSBox {
    init() {
        super.init(frame: .zero)
        boxType = .separator
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

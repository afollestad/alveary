import Foundation
import SwiftUI

struct AppMarkdownTaskCheckbox: View {
    let id: String

    @State private var isChecked: Bool

    init(
        id: String,
        initialValue: Bool
    ) {
        self.id = id
        _isChecked = State(initialValue: AppMarkdownTaskCheckboxStore.value(for: id, defaultValue: initialValue))
    }

    var body: some View {
        Image(systemName: isChecked ? "checkmark.square.fill" : "square")
            .appMarkdownFont(.body)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)
            .frame(width: 16, height: 16)
            // The renderer enables text selection globally; task markers still need
            // to receive taps when they sit beside selectable text.
            .textSelection(.disabled)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("appMarkdownTaskCheckbox")
            .accessibilityLabel(isChecked ? "Completed" : "Incomplete")
            .accessibilityValue(isChecked ? "checked" : "unchecked")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                toggle()
            }
    }

    private func toggle() {
        isChecked.toggle()
        AppMarkdownTaskCheckboxStore.set(isChecked, for: id)
    }
}

enum AppMarkdownTaskCheckboxStore {
    nonisolated(unsafe) private static let cache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 1_000
        return cache
    }()

    static func value(
        for id: String,
        defaultValue: Bool
    ) -> Bool {
        cache.object(forKey: id as NSString)?.boolValue ?? defaultValue
    }

    static func set(
        _ value: Bool,
        for id: String
    ) {
        cache.setObject(NSNumber(value: value), forKey: id as NSString)
    }
}

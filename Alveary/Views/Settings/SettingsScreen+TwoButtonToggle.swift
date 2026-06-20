import SwiftUI

private let twoButtonToggleSelectionAnimation = Animation.interactiveSpring(response: 0.24, dampingFraction: 0.88, blendDuration: 0.12)

/// A compact two-option picker for settings rows that need immediate, binary
/// selection without the weight of a dropdown menu.
struct SettingsTwoButtonToggle<Value: Hashable>: View {
    /// Accessibility label for the grouped control.
    let title: String
    /// The first option shown on the leading side of the control.
    let first: Value
    /// The second option shown on the trailing side of the control.
    let second: Value
    /// Converts an option value into the visible option title.
    let label: (Value) -> String

    @Binding private var selection: Value

    /// Creates a compact two-button toggle bound to a settings value.
    init(
        _ title: String,
        selection: Binding<Value>,
        first: Value,
        second: Value,
        label: @escaping (Value) -> String
    ) {
        self.title = title
        _selection = selection
        self.first = first
        self.second = second
        self.label = label
    }

    var body: some View {
        HStack(spacing: 6) {
            optionButton(for: first)
            optionButton(for: second)
        }
        .backgroundPreferenceValue(SettingsTwoButtonToggleOptionBoundsKey.self) { boundsByOption in
            GeometryReader { proxy in
                if let bounds = boundsByOption[AnyHashable(selection)] {
                    let rect = proxy[bounds]

                    RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous)
                        .fill(selectedBackgroundColor)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .animation(twoButtonToggleSelectionAnimation, value: selection)
                }
            }
            .allowsHitTesting(false)
        }
        .padding(4)
        .frame(height: SettingsScreenLayout.settingsControlSurfaceHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(label(selection))
    }

    private func optionButton(for option: Value) -> some View {
        SettingsTwoButtonToggleOption(
            optionID: AnyHashable(option),
            title: label(option),
            isSelected: option == selection,
            action: { select(option) }
        )
    }

    private func select(_ option: Value) {
        withAnimation(twoButtonToggleSelectionAnimation) {
            selection = option
        }
    }

    private var selectedBackgroundColor: Color {
        Color.secondary.opacity(0.28)
    }
}

private struct SettingsTwoButtonToggleOption: View {
    let optionID: AnyHashable
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(Color.primary.opacity(isSelected ? 1 : 0.55))
                .padding(.horizontal, 12)
                .frame(minWidth: 68, minHeight: 28, maxHeight: 28)
                .contentShape(RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous))
        }
        .buttonStyle(SettingsTwoButtonToggleOptionButtonStyle(isSelected: isSelected, isHovering: isHovering))
        .anchorPreference(key: SettingsTwoButtonToggleOptionBoundsKey.self, value: .bounds) { bounds in
            [optionID: bounds]
        }
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .animation(twoButtonToggleSelectionAnimation, value: isSelected)
    }
}

private struct SettingsTwoButtonToggleOptionButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Group {
                    if !isSelected && (configuration.isPressed || isHovering) {
                        RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous)
                            .fill(unselectedInteractionColor(isPressed: configuration.isPressed))
                    }
                }
            )
    }

    private func unselectedInteractionColor(isPressed: Bool) -> Color {
        isPressed ? Color.primary.opacity(0.10) : Color.primary.opacity(0.06)
    }
}

private struct SettingsTwoButtonToggleOptionBoundsKey: PreferenceKey {
    nonisolated(unsafe) static let defaultValue: [AnyHashable: Anchor<CGRect>] = [:]

    static func reduce(value: inout [AnyHashable: Anchor<CGRect>], nextValue: () -> [AnyHashable: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

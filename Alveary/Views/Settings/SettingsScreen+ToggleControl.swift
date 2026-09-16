import SwiftUI

/// Shares row-click toggling and accessibility between form rows and compact card headers.
/// Only the supplied label is interactive; selectable details belong outside this control.
struct SettingsToggleControl<Content: View>: View {
    private let title: String
    private let helpText: String?
    private let isDisabled: Bool
    private let content: Content
    @Binding private var isOn: Bool

    init(
        _ title: String,
        helpText: String? = nil,
        isOn: Binding<Bool>,
        isDisabled: Bool = false,
        @ViewBuilder content: (SettingsToggleIndicator) -> Content
    ) {
        self.title = title
        self.helpText = helpText
        self.isDisabled = isDisabled
        _isOn = isOn
        self.content = content(SettingsToggleIndicator(title: title, isOn: isOn))
    }

    var body: some View {
        Button {
            guard !isDisabled else { return }
            isOn.toggle()
        } label: {
            content
        }
        .buttonStyle(SettingsToggleRowButtonStyle())
        .disabled(isDisabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint(helpText ?? "")
        .accessibilityAddTraits(.isButton)
    }
}

/// The enclosing button owns interaction, avoiding a second toggle when clicking the switch.
struct SettingsToggleIndicator: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .allowsHitTesting(false)
    }
}

private struct SettingsToggleRowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background {
                if configuration.isPressed && isEnabled {
                    Color.primary.opacity(SettingsScreenLayout.settingsRowPressedOpacity)
                }
            }
    }
}

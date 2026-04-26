import SwiftUI

struct SettingsFormSection<Content: View>: View {
    let title: String?
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    init(@ViewBuilder content: () -> Content) {
        self.title = nil
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsScreenLayout.settingsSectionHeaderSpacing) {
            if let title {
                SettingsFormSectionHeader(title)
            }

            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SettingsScreenLayout.settingsSectionCornerRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
            .clipShape(RoundedRectangle(cornerRadius: SettingsScreenLayout.settingsSectionCornerRadius, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsFormSectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .accessibilityAddTraits(.isHeader)
    }
}

struct SettingsFormRow<Content: View>: View {
    private let showsDivider: Bool
    private let content: Content

    init(
        showsDivider: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.showsDivider = showsDivider
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: SettingsScreenLayout.settingsRowHeight, alignment: .leading)
            .padding(.horizontal, SettingsScreenLayout.settingsRowHorizontalPadding)
            .padding(.vertical, SettingsScreenLayout.settingsRowVerticalPadding)
            .overlay(alignment: .bottom) {
                if showsDivider {
                    Divider()
                        .padding(.horizontal, SettingsScreenLayout.settingsRowHorizontalPadding)
                }
            }
    }
}

struct SettingsToggleRow: View {
    let title: String
    private let showsDivider: Bool
    private let isDisabled: Bool

    @Binding private var isOn: Bool

    init(
        _ title: String,
        isOn: Binding<Bool>,
        showsDivider: Bool = true,
        isDisabled: Bool = false
    ) {
        self.title = title
        _isOn = isOn
        self.showsDivider = showsDivider
        self.isDisabled = isDisabled
    }

    var body: some View {
        Button(action: toggle) {
            SettingsFormRow(showsDivider: showsDivider) {
                SettingsResponsiveControlRow(title, horizontalControlSizing: .intrinsicInline) {
                    Toggle(title, isOn: $isOn)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        .disabled(isDisabled)
                        .allowsHitTesting(false)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .buttonStyle(SettingsToggleRowButtonStyle())
        .disabled(isDisabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }

    private func toggle() {
        guard !isDisabled else {
            return
        }
        isOn.toggle()
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

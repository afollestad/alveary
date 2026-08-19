import AppKit
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

/// A sub-group heading *inside* a `SettingsFormSection` card, for a group whose rows split into
/// concerns too closely related to justify separate cards.
///
/// **A header that follows a row needs `showsDivider: false` on that row.** A hairline plus a
/// label reads as one more row boundary in an evenly spaced run, which is what made the first
/// version disappear; whitespace alone is what marks the break, so the label needs it
/// uninterrupted. The header draws no rule of its own for the same reason.
///
/// Uppercase with tracking at a size the body rows do not use — the label has to differ from a
/// row title by more than colour, which alone is too weak against a dark card.
struct SettingsFormSubsectionHeader: View {
    let title: String
    /// Trims the space above for the header that opens a card, which has no row to separate from.
    let isFirstInSection: Bool

    init(_ title: String, isFirstInSection: Bool = false) {
        self.title = title
        self.isFirstInSection = isFirstInSection
    }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.bold))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SettingsScreenLayout.settingsRowHorizontalPadding)
            .padding(.top, topPadding)
            .padding(.bottom, SettingsScreenLayout.settingsSubsectionHeaderBottomPadding)
            // `textCase` transforms the rendered string, so without this VoiceOver can spell an
            // all-caps title out letter by letter. The uppercasing is presentation only.
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isHeader)
    }

    private var topPadding: CGFloat {
        isFirstInSection
            ? SettingsScreenLayout.settingsSubsectionHeaderFirstTopPadding
            : SettingsScreenLayout.settingsSubsectionHeaderTopPadding
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
    private let helpText: String?
    private let showsDivider: Bool
    private let isDisabled: Bool

    @Binding private var isOn: Bool

    init(
        _ title: String,
        helpText: String? = nil,
        isOn: Binding<Bool>,
        showsDivider: Bool = true,
        isDisabled: Bool = false
    ) {
        self.title = title
        self.helpText = helpText
        _isOn = isOn
        self.showsDivider = showsDivider
        self.isDisabled = isDisabled
    }

    var body: some View {
        Button(action: toggle) {
            SettingsFormRow(showsDivider: showsDivider) {
                SettingsResponsiveControlRow(title, helpText: helpText, horizontalControlSizing: .intrinsicInline) {
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
        .accessibilityHint(helpText ?? "")
        .accessibilityAddTraits(.isButton)
    }

    private func toggle() {
        guard !isDisabled else {
            return
        }
        isOn.toggle()
    }
}

/// Explains why a setting is not doing what its control says, and hands the user the System
/// Settings pane that owns the real answer. macOS keeps the authority for notification
/// authorization and login items, so a toggle here can be overruled from outside the app.
struct SettingsSystemSettingsHintRow: View {
    let message: String
    /// Tried in order; later entries are fallbacks for panes that moved between macOS releases.
    let urlCandidates: [String]

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Open System Settings", action: openSystemSettings)
                .secondaryActionButtonStyle()
        }
    }

    private func openSystemSettings() {
        for urlString in urlCandidates {
            guard let url = URL(string: urlString) else {
                continue
            }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
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

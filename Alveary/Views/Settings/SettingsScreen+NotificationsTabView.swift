import SwiftUI

struct NotificationsSettingsTabView: View {
    let viewModel: SettingsViewModel
    @Binding var notificationsEnabled: Bool
    @Binding var osNotificationsEnabled: Bool
    @Binding var soundEnabled: Bool
    @Binding var soundName: String

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsScreenLayout.settingsSectionSpacing) {
            SettingsFormSection {
                SettingsToggleRow("Enable notifications", isOn: $notificationsEnabled)

                SettingsToggleRow(
                    "Use macOS notifications",
                    isOn: $osNotificationsEnabled,
                    isDisabled: !viewModel.notificationsEnabled
                )

                SettingsToggleRow(
                    "Play sounds",
                    isOn: $soundEnabled,
                    isDisabled: !viewModel.notificationsEnabled
                )

                SettingsFormRow(showsDivider: false) {
                    SettingsResponsiveControlRow("Sound", horizontalControlSizing: .intrinsic) {
                        SettingsMenuPicker(
                            "Sound",
                            selection: $soundName,
                            options: viewModel.availableSoundNames,
                            label: { $0 }
                        )
                        .disabled(!viewModel.notificationsEnabled || !viewModel.soundEnabled)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

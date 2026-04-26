import SwiftUI

struct InterfaceSettingsTabView: View {
    let viewModel: SettingsViewModel
    @Binding var theme: String
    @Binding var codeFontFamily: String
    @Binding var codeFontSize: Int
    @Binding var chatFontSize: Int

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsScreenLayout.settingsSectionSpacing) {
            SettingsFormSection("Appearance") {
                SettingsFormRow {
                    SettingsResponsiveControlRow("Theme", horizontalControlSizing: .intrinsic) {
                        SettingsMenuPicker(
                            "Theme",
                            selection: $theme,
                            options: viewModel.themeOptions,
                            label: { $0.capitalized }
                        )
                    }
                }

                SettingsFormRow {
                    SettingsResponsiveControlRow("Code font family", horizontalControlSizing: .intrinsic) {
                        SettingsMenuPicker(
                            "Code font family",
                            selection: $codeFontFamily,
                            options: viewModel.codeFontFamilyOptions,
                            label: { $0 }
                        )
                    }
                }

                SettingsFormRow {
                    SettingsResponsiveControlRow("Code font size", horizontalControlSizing: .intrinsic) {
                        SettingsValueStepper("Code font size", value: $codeFontSize, in: 10...24)
                    }
                }

                SettingsFormRow(showsDivider: false) {
                    SettingsResponsiveControlRow("Chat font size", horizontalControlSizing: .intrinsic) {
                        SettingsValueStepper("Chat font size", value: $chatFontSize, in: 11...24)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            viewModel.loadCodeFontFamilyOptionsIfNeeded()
        }
    }
}

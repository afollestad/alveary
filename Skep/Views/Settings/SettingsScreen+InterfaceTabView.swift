import SwiftUI

struct InterfaceSettingsTabView: View {
    let viewModel: SettingsViewModel
    @Binding var theme: String
    @Binding var codeFontFamily: String
    @Binding var codeFontSize: Int
    @Binding var chatFontSize: Int

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    ForEach(viewModel.themeOptions, id: \.self) { theme in
                        Text(theme.capitalized).tag(theme)
                    }
                }
                .frame(minHeight: SettingsScreenLayout.settingsRowHeight)

                SettingsTextFieldRow("Code font family", text: $codeFontFamily)
                Stepper(value: $codeFontSize, in: 10...24) {
                    Text("Code font size: \(viewModel.codeFontSize)")
                }
                .frame(minHeight: SettingsScreenLayout.settingsRowHeight)
                Stepper(value: $chatFontSize, in: 11...24) {
                    Text("Chat font size: \(viewModel.chatFontSize)")
                }
                .frame(minHeight: SettingsScreenLayout.settingsRowHeight)
            }
        }
        .formStyle(.grouped)
    }
}

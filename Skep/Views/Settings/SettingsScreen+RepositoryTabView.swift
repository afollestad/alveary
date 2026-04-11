import SwiftUI

struct RepositorySettingsTabView: View {
    @Binding var branchPrefix: String
    @Binding var pushOnCreate: Bool

    var body: some View {
        Form {
            Section("Branching") {
                SettingsTextFieldRow("Branch prefix", text: $branchPrefix)
                Toggle("Push on create", isOn: $pushOnCreate)
                    .frame(minHeight: SettingsScreenLayout.settingsRowHeight)
            }
        }
        .formStyle(.grouped)
    }
}

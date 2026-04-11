import SwiftUI

struct AgentsSettingsTabView: View {
    let providerIDs: [String]
    let providerConfigBinding: (String, WritableKeyPath<ProviderCustomConfig, String?>) -> Binding<String>

    var body: some View {
        Form {
            ForEach(providerIDs, id: \.self) { providerID in
                Section(providerID.capitalized) {
                    SettingsTextFieldRow(
                        "CLI override",
                        text: providerConfigBinding(providerID, \.cli)
                    )
                    SettingsTextFieldRow(
                        "Resume flag",
                        text: providerConfigBinding(providerID, \.resumeFlag)
                    )
                    SettingsTextFieldRow(
                        "Default args",
                        text: providerConfigBinding(providerID, \.defaultArgs)
                    )
                    SettingsTextFieldRow(
                        "Auto-approve flag",
                        text: providerConfigBinding(providerID, \.autoApproveFlag)
                    )
                    SettingsTextFieldRow(
                        "Initial prompt flag",
                        text: providerConfigBinding(providerID, \.initialPromptFlag)
                    )
                    SettingsTextFieldRow(
                        "Extra args",
                        text: providerConfigBinding(providerID, \.extraArgs)
                    )
                }
            }
        }
        .formStyle(.grouped)
    }
}

import SwiftUI

struct GeneralSettingsTabView: View {
    let viewModel: SettingsViewModel
    @Binding var defaultProvider: String
    @Binding var defaultModel: String
    @Binding var permissionMode: String
    @Binding var effort: String
    @Binding var deleteKeyAction: ThreadDeleteKeyAction
    @Binding var autoGenerateNames: Bool
    @Binding var reopenLastThreadAndConversationOnLaunch: Bool
    @Binding var createWorktreeByDefault: Bool
    @Binding var autoTrustWorktrees: Bool
    @Binding var notificationsEnabled: Bool
    @Binding var osNotificationsEnabled: Bool
    @Binding var soundEnabled: Bool
    @Binding var soundName: String

    var body: some View {
        Form {
            Section("Thread Defaults") {
                Picker("Provider", selection: $defaultProvider) {
                    ForEach(viewModel.availableProviderIDs, id: \.self) { providerID in
                        Text(providerID.capitalized).tag(providerID)
                    }
                }
                .frame(minHeight: SettingsScreenLayout.settingsRowHeight)

                Picker("Model", selection: $defaultModel) {
                    ForEach(viewModel.supportedModels, id: \.self) { model in
                        Text(ChatInputFieldTextSupport.modelLabel(for: model)).tag(model)
                    }
                }
                .frame(minHeight: SettingsScreenLayout.settingsRowHeight)

                Picker("Effort", selection: $effort) {
                    ForEach(
                        viewModel.effortOptions(for: viewModel.defaultProvider, model: defaultModel),
                        id: \.self
                    ) { effort in
                        Text(ChatInputFieldTextSupport.effortLabel(for: effort)).tag(effort)
                    }
                }
                .frame(minHeight: SettingsScreenLayout.settingsRowHeight)

                Picker("Permission mode", selection: $permissionMode) {
                    ForEach(viewModel.permissionModeOptions(for: viewModel.defaultProvider), id: \.self) { mode in
                        Text(ChatInputFieldTextSupport.permissionModeLabel(for: mode)).tag(mode)
                    }
                }
                .frame(minHeight: SettingsScreenLayout.settingsRowHeight)

                Picker("Delete key action", selection: $deleteKeyAction) {
                    ForEach(ThreadDeleteKeyAction.allCases, id: \.self) { action in
                        Text(action.label).tag(action)
                    }
                }
                .frame(minHeight: SettingsScreenLayout.settingsRowHeight)

                Toggle("Auto-generate thread names", isOn: $autoGenerateNames)
                    .frame(minHeight: SettingsScreenLayout.settingsRowHeight)
                Toggle("Create worktree by default", isOn: $createWorktreeByDefault)
                    .frame(minHeight: SettingsScreenLayout.settingsRowHeight)
                Toggle("Auto-trust worktrees", isOn: $autoTrustWorktrees)
                    .frame(minHeight: SettingsScreenLayout.settingsRowHeight)
            }

            Section("Startup") {
                Toggle(
                    "Re-open the last thread and conversation on launch",
                    isOn: $reopenLastThreadAndConversationOnLaunch
                )
                .frame(minHeight: SettingsScreenLayout.settingsRowHeight)
            }

            Section("Notifications") {
                Toggle("Enable notifications", isOn: $notificationsEnabled)
                    .frame(minHeight: SettingsScreenLayout.settingsRowHeight)
                Toggle("Use macOS notifications", isOn: $osNotificationsEnabled)
                    .disabled(!viewModel.notificationsEnabled)
                    .frame(minHeight: SettingsScreenLayout.settingsRowHeight)
                Toggle("Play sounds", isOn: $soundEnabled)
                    .disabled(!viewModel.notificationsEnabled)
                    .frame(minHeight: SettingsScreenLayout.settingsRowHeight)

                Picker("Sound", selection: $soundName) {
                    ForEach(viewModel.availableSoundNames, id: \.self) { sound in
                        Text(sound).tag(sound)
                    }
                }
                .disabled(!viewModel.notificationsEnabled || !viewModel.soundEnabled)
                .frame(minHeight: SettingsScreenLayout.settingsRowHeight)
            }
        }
        .formStyle(.grouped)
    }
}

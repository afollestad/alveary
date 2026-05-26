import SwiftUI

struct ThreadsSettingsTabView: View {
    let viewModel: SettingsViewModel
    @Binding var defaultProvider: String
    @Binding var defaultModel: String
    @Binding var permissionMode: String
    @Binding var effort: String
    @Binding var defaultThreadCleanupAction: ThreadCleanupAction
    @Binding var defaultEnterBehavior: ThreadEnterDefaultBehavior
    @Binding var reopenLastThreadAndConversationOnLaunch: Bool
    @Binding var turnAwakeEnabled: Bool
    @Binding var turnAwakePreventDisplaySleep: Bool
    @Binding var createWorktreeByDefault: Bool
    @Binding var autoTrustProjects: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsScreenLayout.settingsSectionSpacing) {
            SettingsFormSection("Defaults") {
                SettingsFormRow {
                    SettingsResponsiveControlRow("Provider", horizontalControlSizing: .intrinsic) {
                        SettingsMenuPicker(
                            "Provider",
                            selection: $defaultProvider,
                            options: viewModel.availableProviderIDs,
                            label: { $0.capitalized }
                        )
                    }
                }

                SettingsFormRow {
                    SettingsResponsiveControlRow("Model", horizontalControlSizing: .intrinsic) {
                        SettingsMenuPicker(
                            "Model",
                            selection: $defaultModel,
                            options: viewModel.supportedModels,
                            label: ChatInputFieldTextSupport.modelLabel(for:)
                        )
                    }
                }

                SettingsFormRow {
                    SettingsResponsiveControlRow("Effort", horizontalControlSizing: .intrinsic) {
                        SettingsMenuPicker(
                            "Effort",
                            selection: $effort,
                            options: viewModel.effortOptions(for: viewModel.defaultProvider, model: defaultModel),
                            label: ChatInputFieldTextSupport.effortLabel(for:)
                        )
                    }
                }

                SettingsFormRow {
                    SettingsResponsiveControlRow("Permission mode", horizontalControlSizing: .intrinsic) {
                        SettingsMenuPicker(
                            "Permission mode",
                            selection: $permissionMode,
                            options: viewModel.permissionModeOptions(for: viewModel.defaultProvider),
                            label: { ChatInputFieldTextSupport.permissionModeLabel(for: $0) }
                        )
                    }
                }

                SettingsFormRow {
                    SettingsResponsiveControlRow(
                        "Default thread cleanup action",
                        helpText: ThreadSettingsHelp.defaultThreadCleanupAction,
                        horizontalControlSizing: .intrinsic
                    ) {
                        SettingsMenuPicker(
                            "Default thread cleanup action",
                            selection: $defaultThreadCleanupAction,
                            options: ThreadCleanupAction.allCases,
                            label: \.label
                        )
                    }
                }

                SettingsFormRow {
                    SettingsResponsiveControlRow(
                        "Default Enter button behavior",
                        helpText: ThreadSettingsHelp.defaultEnterBehavior,
                        horizontalControlSizing: .intrinsic
                    ) {
                        SettingsMenuPicker(
                            "Default Enter button behavior",
                            selection: $defaultEnterBehavior,
                            options: ThreadEnterDefaultBehavior.allCases,
                            label: \.label
                        )
                    }
                }

                SettingsToggleRow(
                    "Create worktree by default",
                    helpText: ThreadSettingsHelp.createWorktreeByDefault,
                    isOn: $createWorktreeByDefault
                )

                SettingsToggleRow(
                    "Auto-trust projects",
                    helpText: ThreadSettingsHelp.autoTrustProjects,
                    isOn: $autoTrustProjects,
                    showsDivider: false
                )
            }

            SettingsFormSection("Startup") {
                SettingsToggleRow(
                    "Re-open the last thread and conversation on launch",
                    isOn: $reopenLastThreadAndConversationOnLaunch,
                    showsDivider: false
                )
            }

            SettingsFormSection("Turns") {
                SettingsToggleRow(
                    "Keep Mac awake during turns",
                    isOn: $turnAwakeEnabled
                )

                SettingsToggleRow(
                    "Keep display awake",
                    isOn: $turnAwakePreventDisplaySleep,
                    showsDivider: false,
                    isDisabled: !turnAwakeEnabled
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum ThreadSettingsHelp {
    static let defaultThreadCleanupAction =
        "Sets what Delete does for a selected thread and which action appears at the trailing edge of thread rows in the left pane."
    static let createWorktreeByDefault =
        "New threads default to creating a worktree instead of using the main project folder. You can override this in the composer."
    static let autoTrustProjects =
        "Skips the trust prompt for projects newly added to Alveary."
    static let defaultEnterBehavior =
        "Queue waits for the current turn to finish. Steer sends immediately and may affect the current turn. Option+Enter uses the inverse action."
}

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

struct TerminalSettingsTabView: View {
    @Binding var expandTerminalWhenActionsRun: Bool
    @Binding var maxTerminalSessions: Int

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsScreenLayout.settingsSectionSpacing) {
            SettingsFormSection {
                SettingsToggleRow(
                    "Expand terminal when actions run",
                    isOn: $expandTerminalWhenActionsRun
                )

                SettingsFormRow(showsDivider: false) {
                    SettingsResponsiveControlRow("Max terminal sessions", horizontalControlSizing: .intrinsic) {
                        SettingsValueStepper(
                            "Max terminal sessions",
                            value: $maxTerminalSessions,
                            in: AppSettings.supportedMaxTerminalSessionsRange,
                            unit: "",
                            accessibilityUnit: "sessions"
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

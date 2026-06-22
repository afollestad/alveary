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
                defaultsSectionRows
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
        .task {
            await viewModel.refreshProviderStatuses()
        }
    }
}

private extension ThreadsSettingsTabView {
    @ViewBuilder
    var defaultsSectionRows: some View {
        SettingsFormRow {
            SettingsResponsiveControlRow("Provider", horizontalControlSizing: .intrinsic) {
                SettingsMenuPicker(
                    "Provider",
                    selection: threadDefaultProviderBinding,
                    options: viewModel.threadDefaultProviderIDs,
                    placeholder: providerPlaceholder,
                    isDisabled: threadDefaultControlsDisabled,
                    label: { viewModel.providerDisplayName(for: $0) }
                )
            }
        }

        SettingsFormRow {
            SettingsResponsiveControlRow("Model", horizontalControlSizing: .intrinsic) {
                SettingsMenuPicker(
                    "Model",
                    selection: threadDefaultModelBinding,
                    options: viewModel.threadDefaultModelOptionValues,
                    placeholder: dependentPlaceholder,
                    isDisabled: threadDefaultControlsDisabled,
                    label: { viewModel.modelLabel(for: $0, providerId: viewModel.threadDefaultProviderSelection) }
                )
            }
        }

        let effortOptions = viewModel.threadDefaultEffortOptions
        if !effortOptions.isEmpty {
            SettingsFormRow {
                SettingsResponsiveControlRow("Effort", horizontalControlSizing: .intrinsic) {
                    SettingsMenuPicker(
                        "Effort",
                        selection: $effort,
                        options: effortOptions.map(\.value),
                        isDisabled: viewModel.isCheckingThreadDefaultProviders,
                        label: { value in
                            effortOptions.first { $0.value == value }?.label
                                ?? ChatComposerTextSupport.effortLabel(for: value)
                        }
                    )
                }
            }
        }

        let permissionModeOptions = viewModel.threadDefaultPermissionModeOptions
        if !permissionModeOptions.isEmpty {
            SettingsFormRow {
                SettingsResponsiveControlRow("Permission mode", horizontalControlSizing: .intrinsic) {
                    SettingsMenuPicker(
                        "Permission mode",
                        selection: $permissionMode,
                        options: permissionModeOptions,
                        isDisabled: viewModel.isCheckingThreadDefaultProviders,
                        label: { viewModel.permissionModeLabel(for: $0, providerId: viewModel.threadDefaultProviderSelection) }
                    )
                }
            }
        }

        SettingsFormRow {
            SettingsResponsiveControlRow(
                "Default thread cleanup action",
                helpText: ThreadSettingsHelp.defaultThreadCleanupAction,
                horizontalControlSizing: .intrinsicInline
            ) {
                SettingsTwoButtonToggle(
                    "Default thread cleanup action",
                    selection: $defaultThreadCleanupAction,
                    first: .archive,
                    second: .delete,
                    label: \.label
                )
            }
        }

        SettingsFormRow {
            SettingsResponsiveControlRow(
                "Default Enter button behavior",
                helpText: ThreadSettingsHelp.defaultEnterBehavior,
                horizontalControlSizing: .intrinsicInline
            ) {
                SettingsTwoButtonToggle(
                    "Default Enter button behavior",
                    selection: $defaultEnterBehavior,
                    first: .queue,
                    second: .steer,
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

    var providerPlaceholder: String? {
        if viewModel.isCheckingThreadDefaultProviders {
            return "Checking providers..."
        }
        return viewModel.hasReadyThreadDefaultProvider ? nil : "No ready providers"
    }

    var dependentPlaceholder: String? {
        threadDefaultControlsDisabled ? providerPlaceholder : nil
    }

    var threadDefaultControlsDisabled: Bool {
        viewModel.isCheckingThreadDefaultProviders || !viewModel.hasReadyThreadDefaultProvider
    }

    var threadDefaultProviderBinding: Binding<String> {
        Binding(
            get: { viewModel.threadDefaultProviderSelection },
            set: { defaultProvider = $0 }
        )
    }

    var threadDefaultModelBinding: Binding<String> {
        Binding(
            get: { viewModel.threadDefaultModelSelection },
            set: { defaultModel = $0 }
        )
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
        "Queue waits for the current turn to finish. Steer sends immediately and may affect the current turn. Cmd+Enter uses the inverse action."
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

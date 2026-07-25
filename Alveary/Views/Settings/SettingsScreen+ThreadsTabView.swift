import SwiftUI

struct ThreadsSettingsTabView: View {
    let viewModel: SettingsViewModel
    @Binding var defaultProvider: String
    @Binding var defaultModel: String
    @Binding var permissionMode: String
    @Binding var effort: String
    @Binding var defaultThreadCleanupAction: ThreadCleanupAction
    @Binding var defaultEnterBehavior: ThreadEnterDefaultBehavior
    @Binding var autoTrustProjects: Bool
    @Binding var reopenLastThreadAndConversationOnLaunch: Bool
    @Binding var turnAwakeEnabled: Bool
    @Binding var turnAwakePreventDisplaySleep: Bool
    @Binding var voiceInputShortcut: PhysicalKeyboardShortcut?
    @Binding var contextManagementEnabled: Bool
    @Binding var sessionHandoffWindowPercentage: Int
    @Binding var handoffSteeringEnabled: Bool
    @Binding var handoffSteeringCountdownSeconds: Int
    @Binding var handoffPromptSendCountdownSeconds: Int
    @Binding var handoffContextCustomizationEnabled: Bool
    @Binding var sessionHandoffPrompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsScreenLayout.settingsSectionSpacing) {
            contextManagementSection

            SettingsFormSection("Defaults") {
                defaultsSectionRows
            }

            SettingsFormSection("Project trust") {
                SettingsToggleRow(
                    "Auto-trust projects",
                    helpText: ProjectTrustSettingsHelp.autoTrustProjects,
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

            SettingsFormSection("Voice Input") {
                SettingsFormRow(showsDivider: false) {
                    SettingsResponsiveControlRow(
                        "Dictation shortcut",
                        helpText: VoiceInputSettingsHelp.shortcut,
                        horizontalControlSizing: .fillsAvailableWidthFraction(0.62)
                    ) {
                        VoiceInputShortcutRecorder(
                            shortcut: $voiceInputShortcut,
                            appShotShortcut: viewModel.appShotShortcut,
                            supportsVoiceInput: VoiceInputPlatform.isSupported
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await viewModel.refreshProviderStatuses()
        }
    }
}

private extension ThreadsSettingsTabView {
    var contextManagementSection: some View {
        SettingsFormSection("Context management") {
            SettingsToggleRow(
                "Enable automatic session handoff",
                helpText: ContextManagementHelp.contextManagementEnabled,
                isOn: $contextManagementEnabled
            )

            SettingsFormRow {
                SettingsResponsiveControlRow(
                    "Session handoff window percentage",
                    helpText: ContextManagementHelp.sessionHandoffWindowPercentage,
                    horizontalControlSizing: .intrinsic
                ) {
                    SettingsValueStepper(
                        "Session handoff window percentage",
                        value: $sessionHandoffWindowPercentage,
                        in: AppSettings.supportedHandoffPercentageRange,
                        step: AppSettings.sessionHandoffWindowPercentageStep,
                        unit: "%",
                        unitSeparator: "",
                        accessibilityUnit: "percent"
                    )
                }
            }
            .disabled(!contextManagementEnabled)

            SettingsPromptEditorRow(
                "Default session handoff prompt",
                helpText: ContextManagementHelp.defaultSessionHandoffPrompt,
                prompt: $sessionHandoffPrompt,
                defaultPrompt: AppSettings.defaultSessionHandoffPrompt,
                placeholder: "Write the prompt used to prepare a session handoff."
            )

            SettingsToggleRow(
                "Enable handoff steering",
                helpText: ContextManagementHelp.handoffSteeringEnabled,
                isOn: $handoffSteeringEnabled,
                isDisabled: !contextManagementEnabled
            )

            SettingsFormRow {
                SettingsResponsiveControlRow(
                    "Handoff steering countdown",
                    helpText: ContextManagementHelp.handoffSteeringCountdown,
                    horizontalControlSizing: .intrinsic
                ) {
                    SettingsValueStepper(
                        "Handoff steering countdown",
                        value: $handoffSteeringCountdownSeconds,
                        in: AppSettings.supportedHandoffSteeringCountdownRange,
                        unit: "s",
                        unitSeparator: "",
                        accessibilityUnit: "seconds"
                    )
                }
            }
            .disabled(!contextManagementEnabled || !handoffSteeringEnabled)

            SettingsToggleRow(
                "Allow handoff context customization",
                helpText: ContextManagementHelp.handoffContextCustomization,
                isOn: $handoffContextCustomizationEnabled
            )

            SettingsFormRow(showsDivider: false) {
                SettingsResponsiveControlRow(
                    "Handoff prompt send countdown",
                    helpText: ContextManagementHelp.handoffPromptSendCountdown,
                    horizontalControlSizing: .intrinsic
                ) {
                    SettingsValueStepper(
                        "Handoff prompt send countdown",
                        value: $handoffPromptSendCountdownSeconds,
                        in: AppSettings.supportedHandoffPromptSendCountdownRange,
                        unit: "s",
                        unitSeparator: "",
                        accessibilityUnit: "seconds"
                    )
                }
            }
        }
    }

    @ViewBuilder
    var defaultsSectionRows: some View {
        SettingsFormRow {
            SettingsResponsiveControlRow("Agent", horizontalControlSizing: .intrinsic) {
                SettingsMenuPicker(
                    "Agent",
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
    }

    var providerPlaceholder: String? {
        if viewModel.isCheckingThreadDefaultProviders {
            return "Checking agents..."
        }
        return viewModel.hasReadyThreadDefaultProvider ? nil : "No ready agents"
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

private enum ProjectTrustSettingsHelp {
    static let autoTrustProjects =
        "Skips the trust prompt for projects newly added to Alveary."
}

private enum ThreadSettingsHelp {
    static let defaultThreadCleanupAction =
        "Sets what Delete does for a selected thread and which action appears at the trailing edge of thread rows in the left pane."
    static let defaultEnterBehavior =
        "Queue waits for the current turn to finish. Steer sends immediately and may affect the current turn. Cmd+Enter uses the inverse action."
}

private enum ContextManagementHelp {
    static let contextManagementEnabled =
        "Automatically starts session handoff when the context window crosses the configured threshold."
    static let sessionHandoffWindowPercentage =
        "Triggers session handoff when the context window reaches this percentage."
    static let defaultSessionHandoffPrompt =
        "Prompt sent to the agent to collect context for the next session."
    static let handoffSteeringEnabled =
        "Lets you steer the handoff output when automatic session handoff starts."
    static let handoffSteeringCountdown =
        "Seconds to enter steering before continuing with the default handoff. " +
        "The countdown stops when you start typing in the composer."
    static let handoffContextCustomization =
        "Lets you edit the generated handoff context before it is sent to the next session. " +
        "This happens after steering."
    static let handoffPromptSendCountdown =
        "Seconds to edit generated handoff context before it is sent automatically to the next session. " +
        "The countdown stops when you start typing in the composer."
}

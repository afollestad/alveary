import SwiftUI

struct ThreadsSettingsTabView: View {
    let viewModel: SettingsViewModel
    @Binding var defaultHarness: String
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

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsScreenLayout.settingsSectionSpacing) {
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
            await viewModel.refreshHarnessStatuses()
        }
    }
}

private extension ThreadsSettingsTabView {
    @ViewBuilder
    var defaultsSectionRows: some View {
        SettingsFormRow {
            SettingsResponsiveControlRow("Harness", horizontalControlSizing: .intrinsic) {
                SettingsMenuPicker(
                    "Harness",
                    selection: threadDefaultHarnessBinding,
                    options: viewModel.threadDefaultHarnessIDs,
                    placeholder: harnessPlaceholder,
                    isDisabled: viewModel.isCheckingThreadDefaultHarnesses || viewModel.threadDefaultHarnessIDs.isEmpty,
                    label: { viewModel.harnessDisplayName(for: $0) }
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
                    label: { viewModel.modelLabel(for: $0, harnessId: viewModel.threadDefaultHarnessSelection) }
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
                        isDisabled: viewModel.isCheckingThreadDefaultHarnesses,
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
                        isDisabled: viewModel.isCheckingThreadDefaultHarnesses,
                        label: { viewModel.permissionModeLabel(for: $0, harnessId: viewModel.threadDefaultHarnessSelection) }
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

        SettingsFormRow(showsDivider: false) {
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

    var harnessPlaceholder: String? {
        if viewModel.isCheckingThreadDefaultHarnesses {
            return "Checking harnesses..."
        }
        return viewModel.threadDefaultHarnessIDs.isEmpty ? "No ready harnesses" : nil
    }

    var dependentPlaceholder: String? {
        threadDefaultControlsDisabled ? harnessPlaceholder : nil
    }

    var threadDefaultControlsDisabled: Bool {
        viewModel.isCheckingThreadDefaultHarnesses || !viewModel.hasReadyThreadDefaultHarness
    }

    var threadDefaultHarnessBinding: Binding<String> {
        Binding(
            get: { viewModel.threadDefaultHarnessSelection },
            set: { defaultHarness = $0 }
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

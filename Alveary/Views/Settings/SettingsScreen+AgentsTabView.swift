import SwiftUI

struct AgentsSettingsTabView: View {
    let viewModel: SettingsViewModel
    let providerIDs: [String]
    let providerExtraArgsBinding: (String) -> Binding<String>

    @Binding var contextManagementEnabled: Bool
    @Binding var sessionHandoffWindowPercentage: Int
    @Binding var handoffSteeringEnabled: Bool
    @Binding var handoffSteeringCountdownSeconds: Int
    @Binding var handoffPromptSendCountdownSeconds: Int
    @Binding var handoffContextCustomizationEnabled: Bool
    @Binding var sessionHandoffPrompt: String

    @State private var isPromptEditorPresented = false
    @State private var promptDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsScreenLayout.settingsSectionSpacing) {
            contextManagementSection

            ForEach(providerIDs, id: \.self) { providerID in
                SettingsFormSection(providerID.capitalized) {
                    SettingsFormRow {
                        providerStatusSection(for: providerID)
                    }

                    SettingsFormRow(showsDivider: false) {
                        SettingsTextFieldRow(
                            "Extra args",
                            text: providerExtraArgsBinding(providerID),
                            horizontalControlSizing: .expandsToFitText
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await viewModel.refreshProviderStatusesIfNeeded()
        }
        .sheet(isPresented: $isPromptEditorPresented) {
            SessionHandoffPromptEditorSheet(
                prompt: $promptDraft,
                onCancel: {
                    isPromptEditorPresented = false
                },
                onSave: {
                    sessionHandoffPrompt = promptDraft
                    isPromptEditorPresented = false
                }
            )
        }
    }
}

private extension AgentsSettingsTabView {
    var contextManagementSection: some View {
        SettingsFormSection("Context management") {
            SettingsToggleRow(
                "Enable automatic session handoff",
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

            SettingsFormRow {
                SettingsResponsiveControlRow(
                    "Default session handoff prompt",
                    helpText: ContextManagementHelp.defaultSessionHandoffPrompt,
                    horizontalControlSizing: .intrinsicInline
                ) {
                    Button("Edit") {
                        promptDraft = sessionHandoffPrompt
                        isPromptEditorPresented = true
                    }
                    .secondaryActionButtonStyle()
                    .disabled(!contextManagementEnabled)
                }
            }
            .disabled(!contextManagementEnabled)

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
                isOn: $handoffContextCustomizationEnabled,
                isDisabled: !contextManagementEnabled
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
            .disabled(!contextManagementEnabled)
        }
    }

    @ViewBuilder
    func providerStatusSection(for providerID: String) -> some View {
        let status = viewModel.providerStatus(for: providerID)

        if status == .unchecked {
            ProgressView("Checking installation status...")
                .frame(maxWidth: .infinity, minHeight: SettingsScreenLayout.settingsRowHeight, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Status")
                    Spacer(minLength: 16)
                    AgentStatusBadge(
                        text: viewModel.shortStatusLabel(for: status),
                        color: viewModel.statusColor(for: status)
                    )
                }

                Text(viewModel.statusDescription(for: status))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if status == .missing, let installCommand = viewModel.installCommand(for: providerID) {
                    Text(installCommand)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                HStack {
                    Button("Refresh Status") {
                        Task {
                            await viewModel.refreshProviderStatuses()
                        }
                    }
                    .secondaryActionButtonStyle()

                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

private enum ContextManagementHelp {
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

private struct SessionHandoffPromptEditorSheet: View {
    @Binding var prompt: String

    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Default session handoff prompt")
                .font(.title3.weight(.semibold))

            AppTextEditor(
                text: $prompt,
                minHeight: 320,
                idealHeight: 360,
                maxHeight: 520,
                placeholder: "Write the prompt used to prepare a session handoff.",
                sizesToContent: false
            )

            HStack {
                Button("Reset") {
                    prompt = AppSettings.defaultSessionHandoffPrompt
                }
                .secondaryActionButtonStyle()
                .disabled(prompt == AppSettings.defaultSessionHandoffPrompt)

                Spacer()

                Button("Cancel", action: onCancel)
                    .secondaryActionButtonStyle()

                Button("Save", action: onSave)
                    .primaryActionButtonStyle()
            }
        }
        .padding(24)
        .frame(minWidth: 620, idealWidth: 720, minHeight: 480)
    }
}

private struct AgentStatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.16)))
    }
}

import AgentCLIKit
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

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsScreenLayout.settingsSectionSpacing) {
            contextManagementSection

            ForEach(providerIDs, id: \.self) { providerID in
                SettingsFormSection(viewModel.providerDisplayName(for: providerID)) {
                    SettingsToggleRow(
                        "Enabled",
                        isOn: Binding(
                            get: { viewModel.isProviderEnabled(providerID) },
                            set: { viewModel.setProvider(providerID, enabled: $0) }
                        )
                    )

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
    }
}

private extension AgentsSettingsTabView {
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
    func providerStatusSection(for providerID: String) -> some View {
        let status = viewModel.providerStatus(for: providerID)

        if isChecking(status) {
            ProgressView("Checking installation status...")
                .frame(maxWidth: .infinity, minHeight: SettingsScreenLayout.settingsRowHeight, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                providerStatusHeader(for: status)

                providerModelsSection(for: providerID)

                Text(viewModel.statusDescription(for: status))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                providerInstallCommandSection(for: providerID, status: status)

                providerDiagnosticsSection(for: status)

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

    func isChecking(_ status: AgentProviderStatus?) -> Bool {
        status?.isEnabled == true && status?.installation == .unknown && status?.setup == .unknown
    }

    func providerStatusHeader(for status: AgentProviderStatus?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Status")
            Spacer(minLength: 16)
            AgentStatusBadge(
                text: viewModel.shortStatusLabel(for: status),
                color: viewModel.statusColor(for: status)
            )
        }
    }

    @ViewBuilder
    func providerModelsSection(for providerID: String) -> some View {
        let modelLabels = viewModel.modelOptionValues(for: providerID).map {
            viewModel.modelLabel(for: $0, providerId: providerID)
        }

        if !modelLabels.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Models")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(modelLabels.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    func providerInstallCommandSection(for providerID: String, status: AgentProviderStatus?) -> some View {
        if status?.installation == .missing, let installCommand = viewModel.installCommand(for: providerID) {
            Text(installCommand)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    func providerDiagnosticsSection(for status: AgentProviderStatus?) -> some View {
        if let status, !status.diagnostics.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(status.diagnostics, id: \.self) { diagnostic in
                    Text(diagnostic)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }
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

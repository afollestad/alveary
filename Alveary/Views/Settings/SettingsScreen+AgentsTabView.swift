import SwiftUI

struct AgentsSettingsTabView: View {
    let viewModel: SettingsViewModel
    let providerIDs: [String]
    let providerExtraArgsBinding: (String) -> Binding<String>

    @Binding var contextManagementEnabled: Bool
    @Binding var sessionHandoffWindowPercentage: Int
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
                SettingsResponsiveControlRow("Session handoff window percentage", horizontalControlSizing: .intrinsic) {
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

            SettingsToggleRow(
                "Allow session handoff context customization",
                isOn: $handoffContextCustomizationEnabled,
                isDisabled: !contextManagementEnabled
            )

            SettingsFormRow(showsDivider: false) {
                SettingsResponsiveControlRow("Default session handoff prompt", horizontalControlSizing: .intrinsicInline) {
                    Button("Edit") {
                        promptDraft = sessionHandoffPrompt
                        isPromptEditorPresented = true
                    }
                    .secondaryActionButtonStyle()
                    .disabled(!contextManagementEnabled)
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

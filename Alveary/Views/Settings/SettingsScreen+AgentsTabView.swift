import SwiftUI

struct AgentsSettingsTabView: View {
    let viewModel: SettingsViewModel
    let providerIDs: [String]
    let providerConfigBinding: (String, WritableKeyPath<ProviderCustomConfig, String?>) -> Binding<String>

    var body: some View {
        Form {
            ForEach(providerIDs, id: \.self) { providerID in
                Section(providerID.capitalized) {
                    providerStatusSection(for: providerID)
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
        .task {
            await viewModel.refreshProviderStatusesIfNeeded()
        }
    }
}

private extension AgentsSettingsTabView {
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

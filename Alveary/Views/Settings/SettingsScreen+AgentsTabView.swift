import AgentCLIKit
import SwiftUI

struct AgentsSettingsTabView: View {
    let viewModel: SettingsViewModel
    let providerIDs: [String]
    let providerExtraArgsBinding: (String) -> Binding<String>

    @Binding var autoTrustProjects: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsScreenLayout.settingsSectionSpacing) {
            SettingsFormSection("Project trust") {
                SettingsToggleRow(
                    "Auto-trust projects",
                    helpText: ProjectTrustSettingsHelp.autoTrustProjects,
                    isOn: $autoTrustProjects,
                    showsDivider: false
                )
            }

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
            await viewModel.refreshProviderStatuses()
        }
    }
}

private extension AgentsSettingsTabView {
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

private enum ProjectTrustSettingsHelp {
    static let autoTrustProjects =
        "Skips the trust prompt for projects newly added to Alveary."
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

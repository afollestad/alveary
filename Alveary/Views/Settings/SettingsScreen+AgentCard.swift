import AgentCLIKit
import SwiftUI

/// One agent's grid cell on the Agents settings tab: name, status, install
/// details, enabled toggle, and extra args. Reuses the untitled
/// `SettingsFormSection` chrome with the agent name inside the card, keeping
/// the cell compact.
struct SettingsAgentCard: View {
    let viewModel: SettingsViewModel
    let providerID: String
    @Binding var extraArgs: String

    var body: some View {
        SettingsFormSection {
            let status = viewModel.providerStatus(for: providerID)

            SettingsFormRow {
                headerAndDetails(for: status)
            }

            SettingsToggleRow(
                "Enabled",
                isOn: Binding(
                    get: { viewModel.isProviderEnabled(providerID) },
                    set: { viewModel.setProvider(providerID, enabled: $0) }
                )
            )

            SettingsFormRow(showsDivider: false) {
                SettingsTextFieldRow(
                    "Extra args",
                    text: $extraArgs,
                    horizontalControlSizing: .expandsToFitText
                )
            }
        }
    }
}

private extension SettingsAgentCard {
    func isChecking(_ status: AgentProviderStatus?) -> Bool {
        status?.isEnabled == true && status?.installation == .unknown && status?.setup == .unknown
    }

    func headerAndDetails(for status: AgentProviderStatus?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(viewModel.providerDisplayName(for: providerID))
                    .font(.headline)

                Spacer(minLength: 16)

                if isChecking(status) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Checking installation status")
                } else {
                    AgentStatusBadge(
                        text: viewModel.shortStatusLabel(for: status),
                        color: viewModel.statusColor(for: status)
                    )
                }
            }

            if isChecking(status) {
                Text("Checking installation status...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                detailsStack(for: status)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    func detailsStack(for status: AgentProviderStatus?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            versionAndPathLine(for: status)

            if viewModel.showsStatusDescription(for: status) {
                Text(viewModel.statusDescription(for: status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            installCommandSection(for: status)

            diagnosticsSection(for: status)
        }
    }

    @ViewBuilder
    func versionAndPathLine(for status: AgentProviderStatus?) -> some View {
        let version = viewModel.providerVersion(for: status)
        let path = viewModel.providerExecutablePath(for: status)

        if version != nil || path != nil {
            versionAndPathText(version: version, path: path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(path ?? version ?? "")
        }
    }

    func versionAndPathText(version: String?, path: String?) -> Text {
        switch (version, path) {
        case let (version?, path?):
            return Text("\(version) · \(Text(path).font(.caption.monospaced()))")
        case let (version?, nil):
            return Text(version)
        case let (nil, path?):
            return Text(path).font(.caption.monospaced())
        case (nil, nil):
            return Text("")
        }
    }

    @ViewBuilder
    func installCommandSection(for status: AgentProviderStatus?) -> some View {
        if status?.installation == .missing, let installCommand = viewModel.installCommand(for: providerID) {
            Text(installCommand)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    func diagnosticsSection(for status: AgentProviderStatus?) -> some View {
        if let status, !status.diagnostics.isEmpty {
            ForEach(status.diagnostics, id: \.self) { diagnostic in
                Text(diagnostic)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
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

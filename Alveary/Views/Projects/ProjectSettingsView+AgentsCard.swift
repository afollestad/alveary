import SwiftUI

struct ProjectSettingsAgentsCard: View {
    let agentRegistry: AgentRegistry
    let providerStatuses: [String: ProviderStatus]
    let allProvidersMissing: Bool
    let statusDescription: (ProviderStatus) -> String
    let shortStatusLabel: (ProviderStatus) -> String
    let statusColor: (ProviderStatus) -> Color
    let onRefresh: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                if providerStatuses.isEmpty || providerStatuses.values.contains(.unchecked) {
                    ProgressView("Checking installed agents...")
                } else if allProvidersMissing {
                    Text("No AI agents found yet. Install one of the supported CLIs below, then refresh.")
                        .foregroundStyle(.secondary)

                    ForEach(agentRegistry.agents.filter { $0.provider != nil }, id: \.id) { agent in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(agent.name)
                                .font(.headline)

                            if let installCommand = agent.installCommand {
                                Text(installCommand)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        )
                    }
                } else {
                    ForEach(agentRegistry.agents.filter { $0.provider != nil }, id: \.id) { agent in
                        let status = providerStatuses[agent.id] ?? .unchecked

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(agent.name)
                                    .font(.headline)
                                Text(statusDescription(status))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(shortStatusLabel(status))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(statusColor(status).opacity(0.16)))
                        }
                    }
                }

                Button("Refresh", action: onRefresh)
                    .secondaryActionButtonStyle()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
        } label: {
            Label("AI Agents", systemImage: "sparkles.rectangle.stack")
        }
    }
}

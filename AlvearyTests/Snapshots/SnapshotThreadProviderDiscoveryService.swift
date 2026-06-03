import AgentCLIKit
import Foundation

actor SnapshotThreadProviderDiscoveryService: AgentCLIKit.AgentProviderDiscoveryService {
    private let statuses: [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] = [
        .claude: AgentCLIKit.AgentProviderStatus(
            providerId: .claude,
            definition: AgentCLIKit.ClaudeProviderDefinition.definition,
            installation: .installed,
            availability: AgentCLIKit.AgentProviderAvailability(
                providerId: .claude,
                executablePath: "/Users/test/.local/bin/claude",
                versionDescription: "2.1.104"
            ),
            setup: .ready,
            modelOptions: AgentCLIKit.AgentDefaultModelOptions.optionsByProvider[.claude] ?? []
        ),
        .codex: AgentCLIKit.AgentProviderStatus(
            providerId: .codex,
            definition: AgentCLIKit.CodexProviderDefinition.definition,
            installation: .missing,
            availability: AgentCLIKit.AgentProviderAvailability(providerId: .codex, executablePath: nil),
            setup: .needsSetup,
            modelOptions: AgentCLIKit.AgentDefaultModelOptions.optionsByProvider[.codex] ?? []
        )
    ]

    func providerStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] {
        statuses
    }

    func installedProviderStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] {
        statuses.filter { $0.value.isInstalled }
    }

    func availableProviderStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] {
        statuses.filter { $0.value.isEnabled && $0.value.installation != .missing }
    }

    func modelOptions(for providerId: AgentCLIKit.AgentProviderID) async -> [AgentCLIKit.AgentModelOption] {
        statuses[providerId]?.modelOptions ?? AgentCLIKit.AgentDefaultModelOptions.providerDefault(for: providerId)
    }

    func stableProviderOrdering() async -> [AgentCLIKit.AgentProviderID] {
        [.claude, .codex]
    }
}

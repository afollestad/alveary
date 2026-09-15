import AgentCLIKit
import Foundation

actor SnapshotThreadHarnessDiscoveryService: AgentCLIKit.AgentHarnessDiscoveryService {
    private let statuses: [AgentCLIKit.AgentHarnessID: AgentCLIKit.AgentHarnessStatus] = [
        .claude: AgentCLIKit.AgentHarnessStatus(
            harnessId: .claude,
            definition: AgentCLIKit.ClaudeHarnessDefinition.definition,
            installation: .installed,
            availability: AgentCLIKit.AgentHarnessAvailability(
                harnessId: .claude,
                executablePath: "/Users/test/.local/bin/claude",
                versionDescription: "2.1.104"
            ),
            setup: .ready,
            modelOptions: AgentModelOptionTestFixtures.claudeModelOptions
        ),
        .codex: AgentCLIKit.AgentHarnessStatus(
            harnessId: .codex,
            definition: AgentCLIKit.CodexHarnessDefinition.definition,
            installation: .missing,
            availability: AgentCLIKit.AgentHarnessAvailability(harnessId: .codex, executablePath: nil),
            setup: .needsSetup,
            modelOptions: AgentModelOptionTestFixtures.codexModelOptions
        )
    ]

    func harnessStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentHarnessID: AgentCLIKit.AgentHarnessStatus] {
        statuses
    }

    func installedHarnessStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentHarnessID: AgentCLIKit.AgentHarnessStatus] {
        statuses.filter { $0.value.isInstalled }
    }

    func availableHarnessStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentHarnessID: AgentCLIKit.AgentHarnessStatus] {
        statuses.filter { $0.value.isEnabled && $0.value.installation != .missing }
    }

    func modelOptions(for harnessId: AgentCLIKit.AgentHarnessID) async -> [AgentCLIKit.AgentModelOption] {
        statuses[harnessId]?.modelOptions ?? AgentCLIKit.AgentDefaultModelOptions.harnessDefault(for: harnessId)
    }

    func stableHarnessOrdering() async -> [AgentCLIKit.AgentHarnessID] {
        [.claude, .codex]
    }
}

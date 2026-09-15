import AgentCLIKit
import Foundation

@testable import Alveary

/// Deterministic harness discovery for settings snapshots: Claude installed
/// and ready, Codex missing. Shared by `SnapshotTests+Settings` and
/// `SnapshotTests+SettingsAgents`.
actor SnapshotHarnessDiscoveryService: AgentCLIKit.AgentHarnessDiscoveryService {
    private let statuses: [AgentCLIKit.AgentHarnessID: AgentCLIKit.AgentHarnessStatus]

    init(statuses: [AgentCLIKit.AgentHarnessID: AgentCLIKit.AgentHarnessStatus]) {
        self.statuses = statuses
    }

    static func defaultStatuses() -> SnapshotHarnessDiscoveryService {
        SnapshotHarnessDiscoveryService(statuses: [
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
        ])
    }

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

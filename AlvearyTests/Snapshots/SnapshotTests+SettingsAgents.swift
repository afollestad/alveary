import AgentCLIKit
import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testSettingsScreenAgentsTab() {
        var settings = AppSettings()
        settings.providerConfigs["claude"] = ProviderCustomConfig(
            extraArgs: "--verbose"
        )

        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(current: settings),
            providerDiscovery: SnapshotProviderDiscoveryService.defaultStatuses(),
            globalAgentInstructionsService: StubInstructionsService(shared: "")
        )

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false),
                appUpdateManager: snapshotAppUpdateManager(),
                onClose: {}
            ),
            size: CGSize(width: 1100, height: 820),
            named: "settings_screen_agents"
        )
    }

    func testSettingsAgentCardReadyState() async {
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(),
            providerDiscovery: SnapshotProviderDiscoveryService.defaultStatuses(),
            globalAgentInstructionsService: StubInstructionsService(shared: "")
        )
        await viewModel.refreshProviderStatuses()

        assertMacSnapshot(
            SettingsAgentCard(
                viewModel: viewModel,
                providerID: "claude",
                extraArgs: .constant("--verbose")
            )
            .padding(24),
            size: CGSize(width: 480, height: 280),
            named: "settings_agent_card_ready"
        )
    }

    func testSettingsScreenAgentsInstructionsSection() async {
        let service = StubInstructionsService(
            shared: "# Shared guidance\n\n@/Users/test/.claude/RTK.md\n\nKeep answers concise.\n"
        )
        service.states = [
            "claude": .linked,
            "codex": .hasOwnFile(path: "/Users/test/.codex/AGENTS.md")
        ]
        let model = GlobalInstructionsEditorModel(service: service, agentRegistry: DefaultAgentRegistry())
        await model.loadIfNeeded()

        assertMacSnapshot(
            AgentsInstructionsSection(model: model)
                .padding(24),
            size: CGSize(width: 720, height: 820),
            named: "settings_agents_instructions_section"
        )
    }

    func testSettingsScreenAgentsTabNarrowStacksSplitInputs() {
        var settings = AppSettings()
        settings.providerConfigs["claude"] = ProviderCustomConfig(
            extraArgs: "--verbose"
        )

        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(current: settings),
            providerDiscovery: SnapshotProviderDiscoveryService.defaultStatuses(),
            globalAgentInstructionsService: StubInstructionsService(shared: "")
        )

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false),
                appUpdateManager: snapshotAppUpdateManager(),
                onClose: {},
                initialTabRawValue: "agents"
            ),
            size: CGSize(width: 400, height: 900),
            named: "settings_screen_agents_narrow_split_inputs"
        )
    }
}

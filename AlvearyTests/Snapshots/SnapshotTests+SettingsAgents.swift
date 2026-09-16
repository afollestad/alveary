import AgentCLIKit
import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testSettingsScreenAgentsTab() async {
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(),
            harnessDiscovery: SnapshotHarnessDiscoveryService.defaultStatuses(),
            globalAgentInstructionsService: StubInstructionsService(shared: "")
        )
        await viewModel.refreshHarnessStatuses()

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false),
                appUpdateManager: snapshotAppUpdateManager(),
                onClose: {},
                initialTabRawValue: "agents"
            ),
            size: CGSize(width: 1100, height: 820),
            named: "settings_screen_agents"
        )
    }

    func testSettingsAgentCardReadyState() async {
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(),
            harnessDiscovery: SnapshotHarnessDiscoveryService.defaultStatuses(),
            globalAgentInstructionsService: StubInstructionsService(shared: "")
        )
        await viewModel.refreshHarnessStatuses()

        assertMacSnapshot(
            SettingsAgentCard(
                viewModel: viewModel,
                harnessID: "claude"
            )
            .padding(24),
            size: CGSize(width: 480, height: 140),
            named: "settings_agent_card_ready"
        )
    }

    func testSettingsAgentCardNarrowKeepsSetupStatusAndSignInVisible() async {
        let discovery = SnapshotHarnessDiscoveryService(statuses: [
            .opencode: AgentHarnessStatus(
                harnessId: .opencode,
                definition: OpenCodeHarnessDefinition.definition,
                installation: .installed,
                availability: AgentHarnessAvailability(
                    harnessId: .opencode,
                    executablePath: "/Users/test/a-long-installation-directory/.opencode/bin/opencode",
                    versionDescription: "1.18.31"
                ),
                setup: .needsSetup
            )
        ])
        let settings = InMemorySettingsService()
        let viewModel = SettingsViewModel(settingsService: settings, harnessDiscovery: discovery)
        await viewModel.refreshHarnessStatuses()
        let signIn = HarnessSignInService(
            agentRegistry: DefaultAgentRegistry(),
            discoveryService: CachingAgentHarnessDiscoveryService(base: discovery),
            settingsService: settings
        )

        assertMacSnapshot(
            SettingsAgentCard(viewModel: viewModel, harnessID: "opencode")
                .environment(signIn)
                .environment(TerminalManager())
                .padding(16),
            size: CGSize(width: 296, height: 230),
            named: "settings_agent_card_narrow_setup",
            colorScheme: .dark
        )
    }

    func testSettingsScreenAgentsInstructionsSection() async {
        let model = await instructionsModel()

        assertMacSnapshot(
            AgentsInstructionsSection(model: model)
                .padding(24),
            size: CGSize(width: 720, height: 320),
            named: "settings_agents_instructions_section"
        )
    }

    /// The dirty state is the only place the sheet's preserved draft is visible once
    /// it closes, so it gets its own baseline.
    func testSettingsScreenAgentsInstructionsSectionDirty() async {
        let model = await instructionsModel()
        model.noteDocumentChanged()

        assertMacSnapshot(
            AgentsInstructionsSection(model: model)
                .padding(24),
            size: CGSize(width: 720, height: 320),
            named: "settings_agents_instructions_section_dirty"
        )
    }

    func testSettingsAgentsInstructionsSheet() async {
        let model = await instructionsModel()

        assertMacSnapshot(
            AgentsInstructionsEditorSheet(model: model, onCancel: {}, onSaved: {}),
            size: CGSize(width: 720, height: 620),
            named: "settings_agents_instructions_sheet"
        )
    }

    func testSettingsScreenAgentsTabNarrowUsesOneColumn() async {
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(),
            harnessDiscovery: SnapshotHarnessDiscoveryService.defaultStatuses(),
            globalAgentInstructionsService: StubInstructionsService(shared: "")
        )
        await viewModel.refreshHarnessStatuses()

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false),
                appUpdateManager: snapshotAppUpdateManager(),
                onClose: {},
                initialTabRawValue: "agents"
            ),
            size: CGSize(width: 400, height: 900),
            named: "settings_screen_agents_narrow_one_column"
        )
    }
}

private extension SnapshotTests {
    @MainActor
    func instructionsModel() async -> GlobalInstructionsEditorModel {
        let service = StubInstructionsService(
            shared: "# Shared guidance\n\n@/Users/test/.claude/RTK.md\n\nKeep answers concise.\n"
        )
        service.states = [
            "claude": .linked,
            "codex": .hasOwnFile(path: "/Users/test/.codex/AGENTS.md")
        ]
        let model = GlobalInstructionsEditorModel(service: service, agentRegistry: DefaultAgentRegistry())
        await model.loadIfNeeded()
        return model
    }
}

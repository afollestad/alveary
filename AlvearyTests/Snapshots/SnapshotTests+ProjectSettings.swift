import XCTest

@testable import Alveary

extension SnapshotTests {
    func testSettingsScreenAgentsTab() {
        var settings = AppSettings()
        settings.providerConfigs["claude"] = ProviderCustomConfig(
            cli: "/Users/test/.local/bin/claude",
            extraArgs: "--verbose"
        )

        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(current: settings),
            providerDetection: SnapshotProviderDetectionService(statuses: [
                "claude": .connected(
                    path: "/Users/test/.local/bin/claude",
                    version: "2.1.104"
                )
            ])
        )

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                onClose: {},
                initialTabRawValue: "agents"
            ),
            size: CGSize(width: 1100, height: 820),
            named: "settings_screen_agents"
        )
    }

    func testProjectSettingsViewHidesGitHubForLocalProject() throws {
        let fixture = try SidebarTestFixture(gitHubInstalledVersion: "gh version 2.89.0", gitHubAuthenticated: false)
        let project = Project(path: "/tmp/local-project", name: "Local Project")
        fixture.context.insert(project)
        try fixture.context.save()

        assertMacSnapshot(
            ProjectSettingsView(
                project: project,
                gitHubCLI: fixture.gitHubCLI
            )
            .modelContainer(fixture.container),
            size: CGSize(width: 1100, height: 900),
            named: "project_settings_local_project"
        )
    }

    func testDiffViewerPaneHeaderOpenPRAction() {
        assertMacSnapshot(
            DiffViewerPaneHeader(
                activeDirectory: "/tmp/alveary",
                contextualAction: .openPR,
                selectedFile: nil,
                areAgentActionsEnabled: true,
                onRefresh: {},
                onCommitRequested: {},
                onOpenPRRequested: {},
                onViewPRRequested: { _ in },
                onStageSelectedFile: {},
                onUnstageSelectedFile: {},
                onDiscardSelectedFile: {}
            ),
            size: CGSize(width: 460, height: 92),
            named: "diff_viewer_header_open_pr"
        )
    }
}

private actor SnapshotProviderDetectionService: ProviderDetectionService {
    private let statuses: [String: ProviderStatus]

    init(statuses: [String: ProviderStatus]) {
        self.statuses = statuses
    }

    func resolvedPath(for providerId: String) -> String? {
        if case let .connected(path, _)? = statuses[providerId] {
            return path
        }
        return nil
    }

    func status(for providerId: String) -> ProviderStatus {
        statuses[providerId] ?? .missing
    }

    func checkAllProviders() async {}

    func checkProvider(_ providerId: String) async {}
}

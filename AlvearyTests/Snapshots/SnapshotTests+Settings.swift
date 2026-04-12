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
                gitHubCLI: SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false),
                onClose: {},
                initialTabRawValue: "agents"
            ),
            size: CGSize(width: 1100, height: 820),
            named: "settings_screen_agents"
        )
    }

    func testSettingsScreenGeneralTab() {
        var settings = AppSettings()
        settings.permissionMode = "acceptEdits"
        settings.effort = "high"
        settings.autoTrustWorktrees = false
        settings.theme = "light"
        settings.codeFontFamily = "JetBrains Mono"
        settings.notifications.soundName = "Pop"

        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService(current: settings))
        let gitHubCLI = SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false)

        assertMacSnapshot(
            SettingsScreen(viewModel: viewModel, gitHubCLI: gitHubCLI, onClose: {}),
            size: CGSize(width: 1100, height: 820),
            named: "settings_screen_general"
        )
    }

    func testSettingsScreenRepositoryTab() {
        var settings = AppSettings()
        settings.branchPrefix = "af"

        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService(current: settings))
        let gitHubCLI = SidebarMockGitHubCLIService(
            installedVersion: "gh version 2.89.0 (2026-03-26)",
            authenticated: true
        )

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: gitHubCLI,
                onClose: {},
                initialTabRawValue: "repository"
            ),
            size: CGSize(width: 1100, height: 820),
            named: "settings_screen_repository"
        )
    }

    func testSettingsScreenRepositoryTabWithoutGitHubCLI() {
        var settings = AppSettings()
        settings.branchPrefix = "af"

        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService(current: settings))
        let gitHubCLI = SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false)

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: gitHubCLI,
                onClose: {},
                initialTabRawValue: "repository"
            ),
            size: CGSize(width: 1100, height: 820),
            named: "settings_screen_repository_no_github_cli"
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

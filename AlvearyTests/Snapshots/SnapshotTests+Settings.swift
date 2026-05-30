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
                onClose: {}
            ),
            size: CGSize(width: 1100, height: 820),
            named: "settings_screen_agents"
        )
    }

    func testSettingsScreenAgentsTabNarrowStacksSplitInputs() {
        var settings = AppSettings()
        settings.providerConfigs["claude"] = ProviderCustomConfig(
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
            size: CGSize(width: 400, height: 900),
            named: "settings_screen_agents_narrow_split_inputs"
        )
    }

    func testSettingsScreenAgentsTabHandoffSteeringDisabled() {
        var settings = AppSettings()
        settings.handoffSteeringEnabled = false
        settings.providerConfigs["claude"] = ProviderCustomConfig(
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
            named: "settings_screen_agents_handoff_steering_disabled"
        )
    }

    func testSettingsHelpTextPopup() {
        assertMacSnapshot(
            AppHoverPopup(horizontalPadding: 12, verticalPadding: 10, textAlignment: .leading) {
                Text("Seconds to enter steering before continuing with the default handoff. " +
                    "The countdown stops when you start typing in the composer.")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 280)
            }
            .padding(24),
            size: CGSize(width: 360, height: 160),
            named: "settings_help_text_popup"
        )
    }

    func testSettingsScreenThreadsTab() {
        var settings = AppSettings()
        settings.permissionMode = "acceptEdits"
        settings.effort = "high"
        settings.autoTrustProjects = false
        settings.theme = "light"
        settings.codeFontFamily = "JetBrains Mono"

        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService(current: settings))
        let gitHubCLI = SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false)

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: gitHubCLI,
                onClose: {},
                initialTabRawValue: "threads"
            ),
            size: CGSize(width: 1100, height: 820),
            named: "settings_screen_threads"
        )
    }

    func testSettingsScreenThreadsTabDark() {
        var settings = AppSettings()
        settings.permissionMode = "acceptEdits"
        settings.effort = "high"
        settings.autoTrustProjects = false
        settings.theme = "dark"
        settings.codeFontFamily = "JetBrains Mono"

        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService(current: settings))
        let gitHubCLI = SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false)

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: gitHubCLI,
                onClose: {},
                initialTabRawValue: "threads"
            ),
            size: CGSize(width: 1100, height: 820),
            named: "settings_screen_threads_dark",
            colorScheme: .dark
        )
    }

    func testSettingsScreenThreadsTabNarrowKeepsTogglesInline() {
        var settings = AppSettings()
        settings.permissionMode = "acceptEdits"
        settings.effort = "high"
        settings.autoTrustProjects = false
        settings.theme = "light"
        settings.codeFontFamily = "JetBrains Mono"

        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService(current: settings))
        let gitHubCLI = SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false)

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: gitHubCLI,
                onClose: {},
                initialTabRawValue: "threads"
            ),
            size: CGSize(width: 400, height: 1_200),
            named: "settings_screen_threads_narrow_toggles"
        )
    }

    func testSettingsScreenNotificationsTab() {
        var settings = AppSettings()
        settings.notifications.soundName = "Pop"

        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService(current: settings))
        let gitHubCLI = SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false)

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: gitHubCLI,
                onClose: {},
                initialTabRawValue: "notifications"
            ),
            size: CGSize(width: 1100, height: 820),
            named: "settings_screen_notifications"
        )
    }

    func testSettingsScreenNotificationsTabNarrowKeepsTogglesInline() {
        var settings = AppSettings()
        settings.notifications.soundName = "Pop"

        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService(current: settings))
        let gitHubCLI = SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false)

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: gitHubCLI,
                onClose: {},
                initialTabRawValue: "notifications"
            ),
            size: CGSize(width: 400, height: 700),
            named: "settings_screen_notifications_narrow_toggles"
        )
    }

    func testSettingsScreenTerminalTab() {
        var settings = AppSettings()
        settings.expandTerminalWhenActionsRun = true
        settings.maxTerminalSessions = 12

        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService(current: settings))
        let gitHubCLI = SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false)

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: gitHubCLI,
                onClose: {},
                initialTabRawValue: "terminal"
            ),
            size: CGSize(width: 1100, height: 820),
            named: "settings_screen_terminal"
        )
    }

    func testSettingsScreenTerminalTabNarrowKeepsControlsInline() {
        var settings = AppSettings()
        settings.expandTerminalWhenActionsRun = true
        settings.maxTerminalSessions = 12

        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService(current: settings))
        let gitHubCLI = SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false)

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: gitHubCLI,
                onClose: {},
                initialTabRawValue: "terminal"
            ),
            size: CGSize(width: 400, height: 700),
            named: "settings_screen_terminal_narrow_controls"
        )
    }

    func testSettingsScreenGitTab() {
        var settings = AppSettings()
        settings.branchPrefix = "af/"

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
                initialTabRawValue: "git"
            ),
            size: CGSize(width: 1100, height: 820),
            named: "settings_screen_git"
        )
    }

    func testSettingsScreenGitTabNarrowStacksSplitInputs() {
        var settings = AppSettings()
        settings.branchPrefix = "af/"

        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService(current: settings))
        let gitHubCLI = SidebarMockGitHubCLIService(
            installedVersion: "gh version 2.90.0 (2026-04-16)",
            authenticated: true
        )

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: gitHubCLI,
                onClose: {},
                initialTabRawValue: "git"
            ),
            size: CGSize(width: 400, height: 900),
            named: "settings_screen_git_narrow_split_inputs"
        )
    }

    func testSettingsScreenGitTabWithoutGitHubCLI() {
        var settings = AppSettings()
        settings.branchPrefix = "af/"

        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService(current: settings))
        let gitHubCLI = SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false)

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: gitHubCLI,
                onClose: {},
                initialTabRawValue: "git"
            ),
            size: CGSize(width: 1100, height: 820),
            named: "settings_screen_git_no_github_cli"
        )
    }

    func testSettingsScreenInterfaceTabCompactLayout() {
        var settings = AppSettings()
        settings.theme = "system"
        settings.codeFontFamily = "SF Mono"
        settings.codeFontSize = 13
        settings.chatFontSize = 14

        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService(current: settings))

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false),
                onClose: {},
                initialTabRawValue: "interface"
            ),
            size: CGSize(width: 620, height: 520),
            named: "settings_screen_interface_compact"
        )
    }

    func testSettingsScreenInterfaceTabNarrowStacksControls() {
        var settings = AppSettings()
        settings.theme = "system"
        settings.codeFontFamily = "SF Mono"
        settings.codeFontSize = 13
        settings.chatFontSize = 14

        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService(current: settings))

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false),
                onClose: {},
                initialTabRawValue: "interface"
            ),
            size: CGSize(width: 400, height: 700),
            named: "settings_screen_interface_narrow_controls"
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

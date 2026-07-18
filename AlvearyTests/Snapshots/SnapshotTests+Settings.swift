import AgentCLIKit
import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testSettingsScreenAgentsTab() {
        var settings = AppSettings()
        settings.autoTrustProjects = true
        settings.providerConfigs["claude"] = ProviderCustomConfig(
            extraArgs: "--verbose"
        )

        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(current: settings),
            providerDiscovery: SnapshotProviderDiscoveryService.defaultStatuses()
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

    func testSettingsScreenAgentsTabNarrowStacksSplitInputs() {
        var settings = AppSettings()
        settings.providerConfigs["claude"] = ProviderCustomConfig(
            extraArgs: "--verbose"
        )

        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(current: settings),
            providerDiscovery: SnapshotProviderDiscoveryService.defaultStatuses()
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

    func testSettingsScreenThreadsTabHandoffSteeringDisabled() {
        var settings = AppSettings()
        settings.contextManagementEnabled = true
        settings.handoffSteeringEnabled = false

        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(current: settings),
            providerDiscovery: SnapshotProviderDiscoveryService.defaultStatuses()
        )

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false),
                appUpdateManager: snapshotAppUpdateManager(),
                onClose: {},
                initialTabRawValue: "threads"
            ),
            size: CGSize(width: 1100, height: 820),
            named: "settings_screen_threads_handoff_steering_disabled"
        )
    }

    func testSettingsHelpTextPopup() {
        assertMacSnapshot(
            settingsHelpTextPopup,
            size: CGSize(width: 360, height: 160),
            named: "settings_help_text_popup"
        )
    }

    func testSettingsHelpTextPopupDark() {
        assertMacSnapshot(
            settingsHelpTextPopup,
            size: CGSize(width: 360, height: 160),
            named: "settings_help_text_popup_dark",
            colorScheme: .dark
        )
    }

    func testSettingsScreenThreadsTab() {
        var settings = AppSettings()
        settings.permissionMode = "acceptEdits"
        settings.effort = "high"
        settings.theme = "light"
        settings.codeFontFamily = "JetBrains Mono"

        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(current: settings),
            providerDiscovery: SnapshotProviderDiscoveryService.defaultStatuses()
        )
        let gitHubCLI = SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false)

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: gitHubCLI,
                appUpdateManager: snapshotAppUpdateManager(),
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
        settings.theme = "dark"
        settings.codeFontFamily = "JetBrains Mono"

        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(current: settings),
            providerDiscovery: SnapshotProviderDiscoveryService.defaultStatuses()
        )
        let gitHubCLI = SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false)

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: gitHubCLI,
                appUpdateManager: snapshotAppUpdateManager(),
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
        settings.theme = "light"
        settings.codeFontFamily = "JetBrains Mono"

        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(current: settings),
            providerDiscovery: SnapshotProviderDiscoveryService.defaultStatuses()
        )
        let gitHubCLI = SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false)

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: gitHubCLI,
                appUpdateManager: snapshotAppUpdateManager(),
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
                appUpdateManager: snapshotAppUpdateManager(),
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
                appUpdateManager: snapshotAppUpdateManager(),
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
                appUpdateManager: snapshotAppUpdateManager(),
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
                appUpdateManager: snapshotAppUpdateManager(),
                onClose: {},
                initialTabRawValue: "terminal"
            ),
            size: CGSize(width: 400, height: 700),
            named: "settings_screen_terminal_narrow_controls"
        )
    }

    func testAppShotsSettingsTab() {
        assertMacSnapshot(
            AppShotsSettingsTabView(
                appShotsEnabled: .constant(true),
                appShotShortcut: .constant(.controlShiftS),
                accessibilityAllowed: true,
                keyboardMonitoringAllowed: false,
                screenRecordingAllowed: false
            )
            .padding(24),
            size: CGSize(width: 620, height: 420),
            named: "settings_app_shots_tab"
        )
    }

    func testAppShotsSettingsHelpDisclosesStoredAccessibilityText() {
        XCTAssertTrue(AppShotsSettingsHelp.enabled.contains("captured accessibility text"))
    }

    func testAppUpdatesSettingsTab() async throws {
        let feed = try snapshotAppUpdateFeed()
        let manager = snapshotAppUpdateManager(result: .installable(feed))
        await manager.forceCheck()
        XCTAssertEqual(manager.lastCheckedAt, Date(timeIntervalSince1970: 1_783_468_800))

        assertMacSnapshot(
            AppUpdatesSettingsTabView(updateManager: manager)
                .padding(24),
            size: CGSize(width: 720, height: 680),
            named: "settings_app_updates_tab"
        )
    }

    func testAppUpdatesSettingsTabDownloadingNarrow() async throws {
        let feed = try snapshotAppUpdateFeed()
        let manager = snapshotDownloadingAppUpdateManager(feed: feed)
        let downloadTask = Task { @MainActor in
            await manager.downloadLatestUpdate()
        }
        try await waitUntil("expected snapshot update download to start") {
            if case .downloading = manager.downloadState {
                return true
            }
            return false
        }

        assertMacSnapshot(
            AppUpdatesSettingsTabView(updateManager: manager)
                .padding(24),
            size: CGSize(width: 440, height: 620),
            named: "settings_app_updates_tab_downloading_narrow"
        )

        manager.cancelDownload()
        _ = await downloadTask.value
    }

    func testAppUpdatesSettingsTabDownloadFailureNarrow() async throws {
        let feed = try snapshotAppUpdateFeed()
        let manager = snapshotFailedDownloadAppUpdateManager(feed: feed)
        await manager.downloadLatestUpdate()

        assertMacSnapshot(
            AppUpdatesSettingsTabView(updateManager: manager)
                .padding(24),
            size: CGSize(width: 440, height: 620),
            named: "settings_app_updates_tab_download_failure_narrow"
        )
    }

    func testSettingsScreenGitTab() {
        var settings = AppSettings()
        settings.branchPrefix = "af/"
        settings.createWorktreeByDefault = true
        settings.lastSettingsPage = .git

        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService(current: settings))
        let gitHubCLI = SidebarMockGitHubCLIService(
            installedVersion: "gh version 2.89.0 (2026-03-26)",
            authenticated: true
        )

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: gitHubCLI,
                appUpdateManager: snapshotAppUpdateManager(),
                onClose: {}
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
                appUpdateManager: snapshotAppUpdateManager(),
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
                appUpdateManager: snapshotAppUpdateManager(),
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

        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService(current: settings))

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false),
                appUpdateManager: snapshotAppUpdateManager(),
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

        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService(current: settings))

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false),
                appUpdateManager: snapshotAppUpdateManager(),
                onClose: {},
                initialTabRawValue: "interface"
            ),
            size: CGSize(width: 400, height: 700),
            named: "settings_screen_interface_narrow_controls"
        )
    }
}

private extension SnapshotTests {
    var settingsHelpTextPopup: some View {
        AppHoverTooltipContent(text: "Seconds to enter steering before continuing with the default handoff. " +
            "The countdown stops when you start typing in the composer.")
        .padding(24)
    }
}

private actor SnapshotProviderDiscoveryService: AgentCLIKit.AgentProviderDiscoveryService {
    private let statuses: [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus]

    init(statuses: [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus]) {
        self.statuses = statuses
    }

    static func defaultStatuses() -> SnapshotProviderDiscoveryService {
        SnapshotProviderDiscoveryService(statuses: [
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
                modelOptions: AgentModelOptionTestFixtures.claudeModelOptions
            ),
            .codex: AgentCLIKit.AgentProviderStatus(
                providerId: .codex,
                definition: AgentCLIKit.CodexProviderDefinition.definition,
                installation: .missing,
                availability: AgentCLIKit.AgentProviderAvailability(providerId: .codex, executablePath: nil),
                setup: .needsSetup,
                modelOptions: AgentModelOptionTestFixtures.codexModelOptions
            )
        ])
    }

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

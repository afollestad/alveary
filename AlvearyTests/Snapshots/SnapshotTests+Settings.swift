import AgentCLIKit
import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
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
        settings.autoTrustProjects = true

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

    func testSettingsScreenMenuBarTab() {
        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService())
        let gitHubCLI = SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false)

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: gitHubCLI,
                appUpdateManager: snapshotAppUpdateManager(),
                onClose: {},
                initialTabRawValue: "menuBar"
            ),
            size: CGSize(width: 1100, height: 820),
            named: "settings_screen_menu_bar"
        )
    }

    func testSettingsScreenMenuBarTabNarrowKeepsToggleInline() {
        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService())
        let gitHubCLI = SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false)

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: gitHubCLI,
                appUpdateManager: snapshotAppUpdateManager(),
                onClose: {},
                initialTabRawValue: "menuBar"
            ),
            size: CGSize(width: 400, height: 700),
            named: "settings_screen_menu_bar_narrow_toggle"
        )
    }

    func testNotificationsSettingsTabSystemDeniedHint() {
        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService())

        assertMacSnapshot(
            NotificationsSettingsTabView(
                viewModel: viewModel,
                notificationsEnabled: .constant(true),
                osNotificationsEnabled: .constant(true),
                soundEnabled: .constant(true),
                soundName: .constant("Glass"),
                systemDeniedOverride: true
            )
            .padding(24),
            size: CGSize(width: 620, height: 420),
            named: "settings_notifications_tab_system_denied"
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

extension SnapshotTests {
    /// One baseline covers the sheet for every packaged prompt: it pins the chrome and the
    /// markdown rendering, not any one prompt's wording. `PromptDefaultsMarkdownRoundTripTests`
    /// owns the hand-wrap check, so a sibling baseline per prompt would only add prose that
    /// reflows on CI.
    func testSettingsPromptEditorSheetShowsTheReviewInstructions() {
        assertMacSnapshot(
            settingsPromptEditorSheet(prompt: AppSettings.defaultPullRequestReviewPrompt),
            size: CGSize(width: 720, height: 620),
            named: "settings_prompt_editor_sheet_review_instructions"
        )
    }

    func testSettingsPromptEditorSheetEmptyShowsItsPlaceholder() {
        assertMacSnapshot(
            settingsPromptEditorSheet(prompt: ""),
            size: CGSize(width: 720, height: 620),
            named: "settings_prompt_editor_sheet_empty"
        )
    }
}

private extension SnapshotTests {
    @MainActor
    func settingsPromptEditorSheet(prompt: String) -> some View {
        SettingsPromptEditorSheet(
            title: "Agentic review instructions",
            draft: AppMarkdownDraft(
                markdown: prompt,
                referenceMarkdown: AppSettings.defaultPullRequestReviewPrompt
            ),
            defaultPrompt: AppSettings.defaultPullRequestReviewPrompt,
            placeholder: "Write the instructions the agent follows when reviewing a pull request.",
            onCancel: {},
            onSave: {}
        )
    }

    var settingsHelpTextPopup: some View {
        AppHoverTooltipContent(text: "Seconds to enter steering before continuing with the default handoff. " +
            "The countdown stops when you start typing in the composer.")
        .padding(24)
    }
}

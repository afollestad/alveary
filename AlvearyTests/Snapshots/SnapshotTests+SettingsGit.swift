import Foundation
import XCTest

@testable import Alveary

/// The Git settings tab. Its `Pull requests` group is the one settings card with in-card
/// sub-headers, so these baselines are what catch a sub-group boundary drifting onto the wrong
/// row. Every one but `WithCustomSidebarSections` takes `SettingsViewModel`'s default empty
/// section loader, which is the disabled `Sidebar section` state.
@MainActor
extension SnapshotTests {
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

    /// The only Git-tab baseline whose `Sidebar section` pickers are enabled — every other one
    /// takes the default empty loader, which covers the disabled state.
    func testSettingsScreenGitTabWithCustomSidebarSections() {
        var settings = AppSettings()
        settings.branchPrefix = "af/"
        settings.pullRequestReviewSectionID = "section-reviews"
        settings.pullRequestAddressFeedbackSectionID = "section-fixes"

        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(current: settings),
            sidebarSectionOptionsLoader: {
                [
                    SettingsSidebarSectionOption(id: "section-reviews", name: "Reviews"),
                    SettingsSidebarSectionOption(id: "section-fixes", name: "Fixes")
                ]
            }
        )
        let gitHubCLI = SidebarMockGitHubCLIService(
            installedVersion: "gh version 2.89.0 (2026-03-26)",
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
            size: CGSize(width: 1100, height: 1250),
            named: "settings_screen_git_custom_sections"
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

    /// Dark is where the sub-headers are weakest — a secondary label on a dark card — and their
    /// separation is whitespace rather than a rule, so this is the baseline that catches a
    /// sub-group boundary going invisible.
    func testSettingsScreenGitTabDarkSubsectionHeaders() {
        var settings = AppSettings()
        settings.branchPrefix = "af/"
        settings.pullRequestReviewSectionID = "section-reviews"
        settings.pullRequestAddressFeedbackSectionID = "section-fixes"

        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(current: settings),
            sidebarSectionOptionsLoader: {
                [
                    SettingsSidebarSectionOption(id: "section-reviews", name: "Reviews"),
                    SettingsSidebarSectionOption(id: "section-fixes", name: "Fixes")
                ]
            }
        )
        let gitHubCLI = SidebarMockGitHubCLIService(
            installedVersion: "gh version 2.89.0 (2026-03-26)",
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
            size: CGSize(width: 1100, height: 1250),
            named: "settings_screen_git_dark_subsection_headers",
            colorScheme: .dark
        )
    }
}

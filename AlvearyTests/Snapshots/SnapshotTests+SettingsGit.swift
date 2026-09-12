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

    func testSettingsScreenGitTabWithReviewTeam() async {
        let viewModel = makeReviewTeamSettingsViewModel()
        await viewModel.refreshProviderStatuses()

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                gitHubCLI: SidebarMockGitHubCLIService(
                    installedVersion: "gh version 2.89.0 (2026-03-26)",
                    authenticated: true
                ),
                appUpdateManager: snapshotAppUpdateManager(),
                onClose: {},
                initialTabRawValue: "git"
            ),
            size: CGSize(width: 1100, height: 1400),
            named: "settings_screen_git_review_team"
        )
    }

    func testPullRequestReviewTeamEditor() async {
        let viewModel = makeReviewTeamSettingsViewModel()
        await viewModel.refreshProviderStatuses()

        assertMacSnapshot(
            PullRequestReviewTeamEditorSheet(
                viewModel: viewModel,
                draft: viewModel.reviewTeamEditorSettings(),
                onCancel: {},
                onSave: { _ in }
            ),
            size: CGSize(width: 760, height: 760),
            named: "pull_request_review_team_editor"
        )
    }

    func testPullRequestReviewTeamEditorDefaults() async {
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(current: AppSettings()),
            providerDiscovery: RecordingProviderDiscoveryService(statuses: ReviewTeamDefaultsFixtures.statuses)
        )
        await viewModel.refreshProviderStatuses()

        assertMacSnapshot(
            PullRequestReviewTeamEditorSheet(
                viewModel: viewModel,
                draft: viewModel.reviewTeamEditorSettings(),
                onCancel: {},
                onSave: { _ in }
            ),
            size: CGSize(width: 760, height: 760),
            named: "pull_request_review_team_editor_defaults"
        )
    }

    func testPullRequestReviewTeamEditorNeedsAttention() async {
        let viewModel = makeReviewTeamSettingsViewModel()
        await viewModel.refreshProviderStatuses()
        let unavailablePeer = PullRequestReviewPeer(
            id: "reviewer-2",
            providerID: "codex",
            model: "gpt-5.5",
            effort: "medium"
        )
        var draft = viewModel.reviewTeamEditorSettings()
        draft.pullRequestReviewPeers = [unavailablePeer]

        assertMacSnapshot(
            PullRequestReviewTeamEditorSheet(
                viewModel: viewModel,
                draft: draft,
                onCancel: {},
                onSave: { _ in }
            ),
            size: CGSize(width: 760, height: 760),
            named: "pull_request_review_team_editor_needs_attention"
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
            size: CGSize(width: 400, height: 1600),
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
            size: CGSize(width: 1100, height: 1700),
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
        settings.pullRequestReviewPermissionMode = "default"
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
            size: CGSize(width: 1100, height: 1400),
            named: "settings_screen_git_dark_subsection_headers",
            colorScheme: .dark
        )
    }
}

private extension SnapshotTests {
    @MainActor
    func makeReviewTeamSettingsViewModel() -> SettingsViewModel {
        var settings = AppSettings()
        settings.branchPrefix = "af/"
        settings.pullRequestReviewMode = .reviewTeam
        settings.pullRequestAddressFeedbackProvider = "claude"
        settings.pullRequestAddressFeedbackModel = "haiku"
        settings.pullRequestAddressFeedbackEffort = "low"
        settings.pullRequestAddressFeedbackPermissionMode = "acceptEdits"
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "reviewer-2", providerID: "claude", model: "fable", effort: "high"),
            PullRequestReviewPeer(id: "reviewer-3", providerID: "claude", model: "opus", effort: "high")
        ]
        return SettingsViewModel(
            settingsService: InMemorySettingsService(current: settings),
            providerDiscovery: SnapshotProviderDiscoveryService.defaultStatuses()
        )
    }
}

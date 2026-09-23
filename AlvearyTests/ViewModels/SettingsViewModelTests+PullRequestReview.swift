import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

/// The Git tab's agentic-review harness pickers: a leading inherit row that persists as
/// nil, and the lockstep clearing that keeps a pinned model from outliving its harness.
@MainActor
extension SettingsViewModelTests {
    /// Lets a test change what the loader answers after the view model is built, which is what
    /// the notification path has to pick up.
    final class MutableSectionOptions {
        var options: [SettingsSidebarSectionOption]

        init(_ options: [SettingsSidebarSectionOption]) {
            self.options = options
        }
    }

    private func reviewViewModel(
        settings: AppSettings = AppSettings(),
        sections: [SettingsSidebarSectionOption] = [],
        sectionStore: MutableSectionOptions? = nil
    ) async -> (SettingsViewModel, InMemorySettingsService) {
        let store = sectionStore ?? MutableSectionOptions(sections)
        let settingsService = InMemorySettingsService(current: settings)
        let viewModel = SettingsViewModel(
            settingsService: settingsService,
            harnessDiscovery: RecordingHarnessDiscoveryService(statuses: [
                .claude: Self.harnessStatus(for: .claude, modelOptions: AgentModelOptionTestFixtures.claudeModelOptions),
                .codex: Self.harnessStatus(for: .codex, modelOptions: AgentModelOptionTestFixtures.codexModelOptions)
            ]),
            sidebarSectionOptionsLoader: { store.options }
        )
        await viewModel.refreshHarnessStatuses()
        viewModel.refreshSidebarSectionOptions()
        return (viewModel, settingsService)
    }

    private static let sectionFixtures = [
        SettingsSidebarSectionOption(id: "section-a", name: "Reviews"),
        SettingsSidebarSectionOption(id: "section-b", name: "Fixes")
    ]

    func testUnpinnedReviewAgentSettingsSelectTheInheritRow() async {
        let (viewModel, _) = await reviewViewModel()

        XCTAssertEqual(viewModel.pullRequestReviewHarnessSelection, SettingsViewModel.pullRequestReviewInheritValue)
        XCTAssertEqual(viewModel.pullRequestReviewModelSelection, SettingsViewModel.pullRequestReviewInheritValue)
        XCTAssertEqual(viewModel.pullRequestReviewEffortSelection, SettingsViewModel.pullRequestReviewInheritValue)
        XCTAssertEqual(viewModel.pullRequestReviewPermissionSelection, SettingsViewModel.pullRequestReviewInheritValue)
        XCTAssertEqual(viewModel.pullRequestReviewLabel(forHarness: SettingsViewModel.pullRequestReviewInheritValue), "Default")
        XCTAssertEqual(viewModel.pullRequestReviewLabel(forPermission: SettingsViewModel.pullRequestReviewInheritValue), "Use thread default")
    }

    func testTheInheritRowLeadsEveryPickerExactlyOnce() async {
        let (viewModel, _) = await reviewViewModel()

        XCTAssertEqual(viewModel.pullRequestReviewHarnessOptions.first, SettingsViewModel.pullRequestReviewInheritValue)
        XCTAssertEqual(viewModel.pullRequestReviewModelOptions.first, SettingsViewModel.pullRequestReviewInheritValue)
        XCTAssertEqual(
            viewModel.pullRequestReviewModelOptions.filter { $0 == SettingsViewModel.pullRequestReviewInheritValue }.count,
            1
        )
        XCTAssertEqual(
            viewModel.pullRequestReviewPermissionOptions,
            [SettingsViewModel.pullRequestReviewInheritValue, "default", "acceptEdits", "auto", "bypassPermissions"]
        )
    }

    func testPickingTheInheritRowClearsTheStoredValue() async {
        var settings = AppSettings()
        settings.pullRequestReviewHarness = "codex"
        settings.pullRequestReviewPermissionMode = "never"
        let (viewModel, settingsService) = await reviewViewModel(settings: settings)
        let initialUpdateCount = settingsService.updateCount

        viewModel.setPullRequestReviewHarness(SettingsViewModel.pullRequestReviewInheritValue)

        XCTAssertNil(settingsService.current.pullRequestReviewHarness)
        XCTAssertNil(settingsService.current.pullRequestReviewPermissionMode)
        XCTAssertEqual(settingsService.updateCount, initialUpdateCount + 1)
    }

    func testPinningAHarnessClearsDependentOverridesInOneWrite() async {
        var settings = AppSettings()
        settings.pullRequestReviewModel = "sonnet"
        settings.pullRequestReviewEffort = "max"
        settings.pullRequestReviewPermissionMode = "bypassPermissions"
        let (viewModel, settingsService) = await reviewViewModel(settings: settings)
        let initialUpdateCount = settingsService.updateCount

        viewModel.setPullRequestReviewHarness("codex")

        XCTAssertEqual(settingsService.current.pullRequestReviewHarness, "codex")
        XCTAssertNil(settingsService.current.pullRequestReviewModel)
        XCTAssertNil(settingsService.current.pullRequestReviewEffort)
        XCTAssertNil(settingsService.current.pullRequestReviewPermissionMode)
        XCTAssertEqual(settingsService.updateCount, initialUpdateCount + 1)
    }

    func testFeedbackAgentEditsLeaveReviewPinsUntouched() async {
        var settings = AppSettings()
        settings.pullRequestReviewAgent = PullRequestAgentSettings(
            harness: "codex", model: "gpt-5.5", effort: "high", permissionMode: "never"
        )
        let (viewModel, settingsService) = await reviewViewModel(settings: settings)

        viewModel.setAddressFeedbackHarness("claude")
        viewModel.setAddressFeedbackModel("haiku")
        viewModel.setAddressFeedbackEffort("low")
        viewModel.setAddressFeedbackPermission("acceptEdits")

        XCTAssertEqual(settingsService.current.pullRequestReviewAgent, settings.pullRequestReviewAgent)
        XCTAssertEqual(
            settingsService.current.pullRequestAddressFeedbackAgent,
            PullRequestAgentSettings(harness: "claude", model: "haiku", effort: "low", permissionMode: "acceptEdits")
        )
        XCTAssertEqual(viewModel.addressFeedbackEffectiveHarnessID, "claude")
        XCTAssertEqual(viewModel.addressFeedbackModelSelection, "haiku")
        XCTAssertEqual(viewModel.addressFeedbackEffortSelection, "low")
        XCTAssertEqual(viewModel.addressFeedbackPermissionSelection, "acceptEdits")

        viewModel.setPullRequestReviewHarness("claude")

        XCTAssertEqual(settingsService.current.pullRequestAddressFeedbackModel, "haiku")
        XCTAssertEqual(settingsService.current.pullRequestAddressFeedbackPermissionMode, "acceptEdits")
    }

    func testFeedbackHarnessChangeClearsOnlyItsDependentPins() async {
        var settings = AppSettings()
        settings.pullRequestAddressFeedbackAgent = PullRequestAgentSettings(
            harness: "claude", model: "sonnet", effort: "high", permissionMode: "acceptEdits"
        )
        let (viewModel, settingsService) = await reviewViewModel(settings: settings)
        let beforeUpdates = settingsService.updateCount

        viewModel.setAddressFeedbackHarness("codex")

        XCTAssertEqual(settingsService.current.pullRequestAddressFeedbackAgent, PullRequestAgentSettings(harness: "codex"))
        XCTAssertEqual(settingsService.updateCount, beforeUpdates + 1)
        XCTAssertTrue(viewModel.addressFeedbackModelOptions.contains("gpt-5.5"))
        XCTAssertFalse(viewModel.addressFeedbackModelOptions.contains("sonnet"))

        viewModel.setAddressFeedbackHarness(SettingsViewModel.pullRequestReviewInheritValue)

        XCTAssertEqual(settingsService.current.pullRequestAddressFeedbackAgent, PullRequestAgentSettings())
        XCTAssertEqual(viewModel.addressFeedbackHarnessSelection, SettingsViewModel.pullRequestReviewInheritValue)
    }

    func testPinningAModelPersistsItAndTheEffortRowFollowsThatModel() async {
        let (viewModel, settingsService) = await reviewViewModel()

        viewModel.setPullRequestReviewModel("haiku")

        XCTAssertEqual(settingsService.current.pullRequestReviewModel, "haiku")
        XCTAssertEqual(viewModel.pullRequestReviewModelSelection, "haiku")
        // Haiku offers low/medium/high, so an xhigh row must not be on the effort picker.
        XCTAssertFalse(viewModel.pullRequestReviewEffortOptions.contains { $0.value == "xhigh" })
    }

    func testSwitchingToAModelThatDropsTheStoredEffortClearsIt() async {
        var settings = AppSettings()
        settings.pullRequestReviewModel = "fable"
        settings.pullRequestReviewEffort = "xhigh"
        let (viewModel, settingsService) = await reviewViewModel(settings: settings)

        viewModel.setPullRequestReviewModel("haiku")

        XCTAssertEqual(settingsService.current.pullRequestReviewModel, "haiku")
        // Haiku has no xhigh; leaving it stored would show an effort the spawn would silently drop.
        XCTAssertNil(settingsService.current.pullRequestReviewEffort)
    }

    func testPickingTheInheritModelRowAlsoClearsTheEffort() async {
        var settings = AppSettings()
        settings.pullRequestReviewModel = "fable"
        settings.pullRequestReviewEffort = "xhigh"
        let (viewModel, settingsService) = await reviewViewModel(settings: settings)

        viewModel.setPullRequestReviewModel(SettingsViewModel.pullRequestReviewInheritValue)

        XCTAssertNil(settingsService.current.pullRequestReviewModel)
        XCTAssertNil(settingsService.current.pullRequestReviewEffort)
    }

    func testPinningAnEffortPersistsItAndTheInheritRowClearsIt() async {
        let (viewModel, settingsService) = await reviewViewModel()

        viewModel.setPullRequestReviewEffort("high")
        XCTAssertEqual(settingsService.current.pullRequestReviewEffort, "high")

        viewModel.setPullRequestReviewEffort(SettingsViewModel.pullRequestReviewInheritValue)
        XCTAssertNil(settingsService.current.pullRequestReviewEffort)
    }

    func testReviewPermissionPersistsAnExplicitDefaultAndClearsTheInheritRow() async {
        var settings = AppSettings()
        settings.permissionMode = "acceptEdits"
        let (viewModel, settingsService) = await reviewViewModel(settings: settings)

        viewModel.setPullRequestReviewPermission("default")

        XCTAssertEqual(settingsService.current.pullRequestReviewPermissionMode, "default")
        XCTAssertEqual(viewModel.pullRequestReviewPermissionSelection, "default")
        XCTAssertEqual(viewModel.pullRequestReviewLabel(forPermission: "default"), "Default (Claude)")
        XCTAssertEqual(settingsService.current.permissionMode, "acceptEdits")

        viewModel.setPullRequestReviewPermission(SettingsViewModel.pullRequestReviewInheritValue)

        XCTAssertNil(settingsService.current.pullRequestReviewPermissionMode)
        XCTAssertEqual(viewModel.pullRequestReviewPermissionSelection, SettingsViewModel.pullRequestReviewInheritValue)
    }

    func testAnUnavailableReviewHarnessShowsInheritedPermissionWithoutDiscardingThePin() async {
        var settings = AppSettings()
        settings.pullRequestReviewHarness = "codex"
        settings.pullRequestReviewPermissionMode = "never"
        let settingsService = InMemorySettingsService(current: settings)
        let viewModel = SettingsViewModel(
            settingsService: settingsService,
            harnessDiscovery: RecordingHarnessDiscoveryService(statuses: [
                .claude: Self.harnessStatus(for: .claude, modelOptions: AgentModelOptionTestFixtures.claudeModelOptions)
            ])
        )
        await viewModel.refreshHarnessStatuses()
        let initialUpdateCount = settingsService.updateCount

        XCTAssertEqual(viewModel.pullRequestReviewEffectiveHarnessID, "claude")
        XCTAssertEqual(viewModel.pullRequestReviewPermissionSelection, SettingsViewModel.pullRequestReviewInheritValue)
        XCTAssertEqual(settingsService.current.pullRequestReviewPermissionMode, "never")
        XCTAssertEqual(settingsService.updateCount, initialUpdateCount)

        XCTAssertTrue(viewModel.pullRequestReviewPermissionOptions.contains("acceptEdits"))
        viewModel.setPullRequestReviewPermission("acceptEdits")

        XCTAssertEqual(settingsService.current.pullRequestReviewHarness, "codex")
        XCTAssertEqual(settingsService.current.pullRequestReviewPermissionMode, "acceptEdits")
        XCTAssertEqual(viewModel.pullRequestReviewPermissionSelection, "acceptEdits")
    }

    func testTheReviewPromptPassesThroughToSettings() async {
        let (viewModel, settingsService) = await reviewViewModel()

        viewModel.pullRequestReviewPrompt = "Only look at the tests."

        XCTAssertEqual(settingsService.current.pullRequestReviewPrompt, "Only look at the tests.")
        XCTAssertEqual(viewModel.pullRequestReviewPrompt, "Only look at the tests.")
    }

    func testReviewModeDefaultsToSingleAndPersistsTeam() async {
        let (viewModel, settingsService) = await reviewViewModel()

        XCTAssertEqual(viewModel.pullRequestReviewMode, .singleAgent)

        viewModel.setPullRequestReviewMode(.reviewTeam)

        XCTAssertEqual(settingsService.current.pullRequestReviewMode, .reviewTeam)
    }

    func testPeerSeedingUsesTheStrictResolvedLeadModel() async {
        var settings = AppSettings()
        settings.defaultHarness = "claude"
        settings.defaultModel = "fable"
        settings.pullRequestReviewHarness = "codex"
        let (viewModel, _) = await reviewViewModel(settings: settings)

        XCTAssertEqual(
            viewModel.defaultPullRequestReviewPeer(harnessID: "codex", excluding: [])?.model,
            "gpt-5.4-mini"
        )
    }

    func testReviewTeamRefreshPreservesAnUnavailableInheritedHarness() async {
        var settings = AppSettings()
        settings.pullRequestReviewMode = .reviewTeam
        settings.defaultHarness = "codex"
        settings.defaultModel = "gpt-5.5"
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer-1", harnessID: "claude", model: "sonnet", effort: "high")
        ]
        let settingsService = InMemorySettingsService(current: settings)
        let viewModel = SettingsViewModel(
            settingsService: settingsService,
            harnessDiscovery: RecordingHarnessDiscoveryService(statuses: [
                .claude: Self.harnessStatus(for: .claude, modelOptions: AgentModelOptionTestFixtures.claudeModelOptions),
                .codex: Self.harnessStatus(
                    for: .codex,
                    installation: .missing,
                    modelOptions: AgentModelOptionTestFixtures.codexModelOptions
                )
            ])
        )

        await viewModel.refreshHarnessStatuses()

        XCTAssertEqual(settingsService.current.defaultHarness, "codex")
        XCTAssertEqual(settingsService.current.defaultModel, "gpt-5.5")
        XCTAssertEqual(
            viewModel.pullRequestReviewTeamSettingsStatus,
            .needsAttention("Lead uses codex, which is not ready.")
        )
    }

    func testReviewTeamRefreshPreservesAStaleInheritedModel() async {
        var settings = AppSettings()
        settings.pullRequestReviewMode = .reviewTeam
        settings.defaultHarness = "claude"
        settings.defaultModel = "retired-model"
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer-1", harnessID: "codex", model: "gpt-5.5", effort: "medium")
        ]
        let (viewModel, settingsService) = await reviewViewModel(settings: settings)

        XCTAssertEqual(settingsService.current.defaultModel, "retired-model")
        XCTAssertEqual(
            viewModel.pullRequestReviewTeamSettingsStatus,
            .needsAttention("Lead uses retired-model, which is not a concrete available model.")
        )
    }

    func testReviewTeamPeerOptionsDoNotUseStaticCatalogFallbacks() async {
        var settings = AppSettings()
        settings.defaultHarness = "codex"
        settings.defaultModel = "gpt-5.5"
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(current: settings),
            harnessDiscovery: RecordingHarnessDiscoveryService(statuses: [
                .claude: Self.harnessStatus(for: .claude, modelOptions: []),
                .codex: Self.harnessStatus(
                    for: .codex,
                    modelOptions: AgentModelOptionTestFixtures.codexModelOptions
                )
            ])
        )
        await viewModel.refreshHarnessStatuses()
        let stalePeer = PullRequestReviewPeer(
            id: "peer-1",
            harnessID: "claude",
            model: "sonnet",
            effort: "high"
        )

        XCTAssertNil(viewModel.defaultPullRequestReviewPeer(harnessID: "claude", excluding: []))
        XCTAssertEqual(viewModel.pullRequestReviewPeerModelOptions(stalePeer), ["sonnet"])
        guard case .needsAttention = viewModel.pullRequestReviewTeamSettingsStatus(peers: [stalePeer]) else {
            return XCTFail("Expected the absent live catalog to need attention")
        }
    }

    func testInvalidPeerPinsRemainSavedAndReportNeedsAttention() async {
        var settings = AppSettings()
        let stalePeer = PullRequestReviewPeer(
            id: "peer-1",
            harnessID: "codex",
            model: "retired-model",
            effort: "medium"
        )
        settings.pullRequestReviewPeers = [stalePeer]
        let (viewModel, settingsService) = await reviewViewModel(settings: settings)

        guard case .needsAttention = viewModel.pullRequestReviewTeamSettingsStatus else {
            return XCTFail("Expected an invalid model pin to need attention")
        }
        XCTAssertEqual(settingsService.current.pullRequestReviewPeers, [stalePeer])
        XCTAssertTrue(viewModel.pullRequestReviewPeerModelOptions(stalePeer).contains("retired-model"))
    }

    func testAPinnedHarnessSuppliesModelAndPermissionOptions() async {
        var settings = AppSettings()
        settings.pullRequestReviewHarness = "codex"
        let (viewModel, _) = await reviewViewModel(settings: settings)

        XCTAssertEqual(viewModel.pullRequestReviewEffectiveHarnessID, "codex")
        XCTAssertTrue(viewModel.pullRequestReviewModelOptions.contains("gpt-5.5"))
        XCTAssertFalse(viewModel.pullRequestReviewModelOptions.contains("sonnet"))
        XCTAssertEqual(
            viewModel.pullRequestReviewPermissionOptions,
            [SettingsViewModel.pullRequestReviewInheritValue, "untrusted", "on-request", "never"]
        )
        // Every review task launches in a network-less sandbox, so its route never offers full access.
        XCTAssertEqual(viewModel.pullRequestReviewLabel(forPermission: "never"), "Never ask")
    }

    /// Addressing feedback keeps shell network to push, so its route still means full access.
    func testOnlyTheReviewRouteDescribesCodexNeverAsSandboxed() async {
        var settings = AppSettings()
        settings.pullRequestAddressFeedbackHarness = "codex"
        let (viewModel, _) = await reviewViewModel(settings: settings)

        XCTAssertEqual(viewModel.addressFeedbackLabel(forPermission: "never"), "Full access")
    }

    func testTasksLeadsBothSectionPickersAsTheNilRow() async {
        let (viewModel, _) = await reviewViewModel(sections: Self.sectionFixtures)

        XCTAssertEqual(viewModel.pullRequestSectionOptions, [nil, "section-a", "section-b"])
        XCTAssertEqual(viewModel.pullRequestSectionLabel(for: nil), "Tasks")
        XCTAssertEqual(viewModel.pullRequestSectionLabel(for: "section-b"), "Fixes")
        XCTAssertNil(viewModel.pullRequestReviewSection)
        XCTAssertNil(viewModel.pullRequestAddressFeedbackSection)
    }

    func testTheTwoRoutesPinSectionsIndependently() async {
        let (viewModel, settingsService) = await reviewViewModel(sections: Self.sectionFixtures)

        viewModel.setPullRequestReviewSection("section-a")
        viewModel.setPullRequestAddressFeedbackSection("section-b")

        XCTAssertEqual(settingsService.current.pullRequestReviewSectionID, "section-a")
        XCTAssertEqual(settingsService.current.pullRequestAddressFeedbackSectionID, "section-b")
        XCTAssertEqual(viewModel.pullRequestReviewSection, "section-a")
        XCTAssertEqual(viewModel.pullRequestAddressFeedbackSection, "section-b")
    }

    func testPickingTasksClearsAPinnedSection() async {
        var settings = AppSettings()
        settings.pullRequestReviewSectionID = "section-a"
        let (viewModel, settingsService) = await reviewViewModel(
            settings: settings,
            sections: Self.sectionFixtures
        )

        viewModel.setPullRequestReviewSection(nil)

        XCTAssertNil(settingsService.current.pullRequestReviewSectionID)
    }

    func testARemovedSectionReadsAsTasksWithoutDiscardingThePin() async {
        var settings = AppSettings()
        settings.pullRequestReviewSectionID = "section-gone"
        let (viewModel, settingsService) = await reviewViewModel(
            settings: settings,
            sections: Self.sectionFixtures
        )

        XCTAssertNil(viewModel.pullRequestReviewSection)
        XCTAssertEqual(viewModel.pullRequestSectionLabel(for: viewModel.pullRequestReviewSection), "Tasks")
        // Reading must not write: re-creating the section has to restore the pick.
        XCTAssertEqual(settingsService.current.pullRequestReviewSectionID, "section-gone")
    }

    func testWithNoCustomSectionsTasksIsTheOnlyOption() async {
        var settings = AppSettings()
        settings.pullRequestAddressFeedbackSectionID = "section-a"
        let (viewModel, _) = await reviewViewModel(settings: settings)

        XCTAssertTrue(viewModel.sidebarSectionOptions.isEmpty)
        XCTAssertEqual(viewModel.pullRequestSectionOptions, [nil])
        XCTAssertNil(viewModel.pullRequestAddressFeedbackSection)
    }

    /// The sidebar sees section changes through its own `@Query`; an open Settings screen learns
    /// about them only through this notification.
    func testTheSectionPickersReloadWhenTheSectionsChangeNotificationFires() async {
        let store = MutableSectionOptions([])
        let (viewModel, _) = await reviewViewModel(sectionStore: store)
        XCTAssertTrue(viewModel.sidebarSectionOptions.isEmpty)

        store.options = Self.sectionFixtures

        // Posted inside the loop, not once ahead of it: `NotificationCenter.Notifications`
        // registers its observer on first iteration, and nothing here guarantees the observation
        // task has reached that point yet — a single post can land before anyone is listening.
        let deadline = Date().addingTimeInterval(2)
        while viewModel.sidebarSectionOptions.isEmpty, Date() < deadline {
            NotificationCenter.default.post(name: .sidebarSectionsChanged, object: nil)
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(viewModel.sidebarSectionOptions.map(\.name), ["Reviews", "Fixes"])
    }
}

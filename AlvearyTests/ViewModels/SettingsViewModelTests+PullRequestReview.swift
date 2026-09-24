import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

/// The Git tab's agentic-review agent pickers: a leading inherit row that persists as nil, and the
/// permission clearing that keeps a pinned permission from outliving its harness.
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
        let editor = viewModel.reviewAgentEditor

        XCTAssertTrue(editor.presentation.isInherited)
        XCTAssertEqual(editor.presentation.inheritOption?.isSelected, true)
        XCTAssertEqual(editor.presentation.buttonTitle, "Default (Claude · Sonnet)")
        XCTAssertEqual(editor.permissionSelection, SettingsViewModel.pullRequestReviewInheritValue)
        XCTAssertEqual(editor.label(forPermission: SettingsViewModel.pullRequestReviewInheritValue), "Use thread default")
    }

    func testTheInheritRowLeadsTheAgentAndPermissionPickersExactlyOnce() async {
        let (viewModel, _) = await reviewViewModel()
        let editor = viewModel.reviewAgentEditor

        XCTAssertEqual(editor.presentation.inheritOption?.title, "Threads default")
        XCTAssertFalse(editor.presentation.modelGroups.contains { group in
            group.options.contains { $0.value == SettingsViewModel.pullRequestReviewInheritValue }
        })
        XCTAssertEqual(
            editor.permissionOptions,
            [SettingsViewModel.pullRequestReviewInheritValue, "default", "acceptEdits", "auto", "bypassPermissions"]
        )
    }

    func testPickingTheInheritRowClearsEveryStoredPinInOneWrite() async {
        var settings = AppSettings()
        settings.pullRequestReviewAgent = PullRequestAgentSettings(
            harness: "codex", model: "gpt-5.5", effort: "high", permissionMode: "never"
        )
        let (viewModel, settingsService) = await reviewViewModel(settings: settings)
        let editor = viewModel.reviewAgentEditor
        let initialUpdateCount = settingsService.updateCount

        pickAgentInherit(in: editor.presentation) { editor.apply($0) }

        XCTAssertEqual(settingsService.current.pullRequestReviewAgent, PullRequestAgentSettings())
        XCTAssertEqual(settingsService.updateCount, initialUpdateCount + 1)
    }

    func testPickingAnotherHarnessesModelWritesAWholePinAndClearsPermissionInOneWrite() async {
        var settings = AppSettings()
        settings.pullRequestReviewModel = "sonnet"
        settings.pullRequestReviewEffort = "max"
        settings.pullRequestReviewPermissionMode = "bypassPermissions"
        let (viewModel, settingsService) = await reviewViewModel(settings: settings)
        let editor = viewModel.reviewAgentEditor
        let initialUpdateCount = settingsService.updateCount

        pickAgentModel("gpt-5.5", harnessID: "codex", in: editor.presentation) { editor.apply($0) }

        XCTAssertEqual(
            settingsService.current.pullRequestReviewAgent,
            PullRequestAgentSettings(harness: "codex", model: "gpt-5.5", effort: "medium")
        )
        XCTAssertEqual(settingsService.updateCount, initialUpdateCount + 1)
    }

    func testFeedbackAgentEditsLeaveReviewPinsUntouched() async {
        var settings = AppSettings()
        settings.pullRequestReviewAgent = PullRequestAgentSettings(
            harness: "codex", model: "gpt-5.5", effort: "high", permissionMode: "never"
        )
        let (viewModel, settingsService) = await reviewViewModel(settings: settings)
        let feedback = viewModel.addressFeedbackAgentEditor

        feedback.setPermission("acceptEdits")
        pickAgentModel("haiku", harnessID: "claude", in: feedback.presentation) { feedback.apply($0) }
        dragAgentEffort("low", in: feedback.presentation) { feedback.apply($0) }

        XCTAssertEqual(settingsService.current.pullRequestReviewAgent, settings.pullRequestReviewAgent)
        // Pinning the harness the route already inherited keeps its permission.
        XCTAssertEqual(
            settingsService.current.pullRequestAddressFeedbackAgent,
            PullRequestAgentSettings(harness: "claude", model: "haiku", effort: "low", permissionMode: "acceptEdits")
        )
        XCTAssertEqual(feedback.presentation.selection.modelID, "haiku")
        XCTAssertEqual(feedback.presentation.selection.effortValue, "low")
        XCTAssertEqual(feedback.permissionSelection, "acceptEdits")

        let review = viewModel.reviewAgentEditor
        pickAgentModel("sonnet", harnessID: "claude", in: review.presentation) { review.apply($0) }

        XCTAssertEqual(settingsService.current.pullRequestAddressFeedbackModel, "haiku")
        XCTAssertEqual(settingsService.current.pullRequestAddressFeedbackPermissionMode, "acceptEdits")
    }

    func testFeedbackHarnessChangeClearsOnlyItsDependentPins() async {
        var settings = AppSettings()
        settings.pullRequestAddressFeedbackAgent = PullRequestAgentSettings(
            harness: "claude", model: "sonnet", effort: "high", permissionMode: "acceptEdits"
        )
        let (viewModel, settingsService) = await reviewViewModel(settings: settings)
        let feedback = viewModel.addressFeedbackAgentEditor
        let beforeUpdates = settingsService.updateCount

        pickAgentModel("gpt-5.5", harnessID: "codex", in: feedback.presentation) { feedback.apply($0) }

        XCTAssertEqual(
            settingsService.current.pullRequestAddressFeedbackAgent,
            PullRequestAgentSettings(harness: "codex", model: "gpt-5.5", effort: "high")
        )
        XCTAssertEqual(settingsService.updateCount, beforeUpdates + 1)
        XCTAssertEqual(feedback.presentation.selection.harnessID, "codex")

        pickAgentInherit(in: feedback.presentation) { feedback.apply($0) }

        XCTAssertEqual(settingsService.current.pullRequestAddressFeedbackAgent, PullRequestAgentSettings())
        XCTAssertTrue(feedback.presentation.isInherited)
    }

    func testPinningAModelPersistsItAndTheEffortSliderFollowsThatModel() async {
        let (viewModel, settingsService) = await reviewViewModel()
        let editor = viewModel.reviewAgentEditor

        pickAgentModel("haiku", harnessID: "claude", in: editor.presentation) { editor.apply($0) }

        XCTAssertEqual(settingsService.current.pullRequestReviewModel, "haiku")
        XCTAssertEqual(editor.presentation.selection.modelID, "haiku")
        // Haiku offers low/medium/high, so the slider must not offer xhigh.
        XCTAssertFalse(editor.presentation.selection.effortOptions.contains { $0.value == "xhigh" })
    }

    func testSwitchingToAModelThatDropsTheStoredEffortFallsToThatModelsDefault() async {
        var settings = AppSettings()
        settings.pullRequestReviewModel = "fable"
        settings.pullRequestReviewEffort = "xhigh"
        let (viewModel, settingsService) = await reviewViewModel(settings: settings)
        let editor = viewModel.reviewAgentEditor

        pickAgentModel("haiku", harnessID: "claude", in: editor.presentation) { editor.apply($0) }

        XCTAssertEqual(settingsService.current.pullRequestReviewModel, "haiku")
        // Haiku has no xhigh; leaving it stored would show an effort the spawn would silently drop.
        XCTAssertEqual(settingsService.current.pullRequestReviewEffort, "medium")
    }

    func testDraggingEffortWhileInheritedPinsTheResolvedAgent() async {
        let (viewModel, settingsService) = await reviewViewModel()
        let editor = viewModel.reviewAgentEditor
        let inherited = editor.presentation.effective

        dragAgentEffort("high", in: editor.presentation) { editor.apply($0) }

        XCTAssertEqual(
            settingsService.current.pullRequestReviewAgent,
            PullRequestAgentSettings(harness: inherited.harness.id, model: inherited.model, effort: "high")
        )
    }

    func testReviewPermissionPersistsAnExplicitDefaultAndClearsTheInheritRow() async {
        var settings = AppSettings()
        settings.permissionMode = "acceptEdits"
        let (viewModel, settingsService) = await reviewViewModel(settings: settings)
        let editor = viewModel.reviewAgentEditor

        editor.setPermission("default")

        XCTAssertEqual(settingsService.current.pullRequestReviewPermissionMode, "default")
        XCTAssertEqual(editor.permissionSelection, "default")
        XCTAssertEqual(editor.label(forPermission: "default"), "Default (Claude)")
        XCTAssertEqual(settingsService.current.permissionMode, "acceptEdits")

        editor.setPermission(SettingsViewModel.pullRequestReviewInheritValue)

        XCTAssertNil(settingsService.current.pullRequestReviewPermissionMode)
        XCTAssertEqual(editor.permissionSelection, SettingsViewModel.pullRequestReviewInheritValue)
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
        let editor = viewModel.reviewAgentEditor
        let initialUpdateCount = settingsService.updateCount

        XCTAssertEqual(editor.effectiveHarnessID, "claude")
        XCTAssertEqual(editor.presentation.buttonTitle, "Claude · Sonnet")
        XCTAssertEqual(editor.permissionSelection, SettingsViewModel.pullRequestReviewInheritValue)
        XCTAssertEqual(settingsService.current.pullRequestReviewPermissionMode, "never")
        XCTAssertEqual(settingsService.updateCount, initialUpdateCount)

        XCTAssertTrue(editor.permissionOptions.contains("acceptEdits"))
        editor.setPermission("acceptEdits")

        XCTAssertEqual(settingsService.current.pullRequestReviewHarness, "codex")
        XCTAssertEqual(settingsService.current.pullRequestReviewPermissionMode, "acceptEdits")
        XCTAssertEqual(editor.permissionSelection, "acceptEdits")
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
        // An empty live catalog offers only the stale pin's repair row, never a synthesized harness default.
        let staleGroup = viewModel.reviewTeamPeerPresentation(stalePeer).modelGroups.first { $0.harnessID == "claude" }
        XCTAssertEqual(staleGroup?.options.map(\.value), ["sonnet"])
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
        XCTAssertEqual(viewModel.reviewTeamPeerPresentation(stalePeer).selection.modelID, "retired-model")
    }

    func testAPinnedHarnessSuppliesModelAndPermissionOptions() async {
        var settings = AppSettings()
        settings.pullRequestReviewHarness = "codex"
        let (viewModel, _) = await reviewViewModel(settings: settings)

        let editor = viewModel.reviewAgentEditor

        XCTAssertEqual(editor.effectiveHarnessID, "codex")
        XCTAssertEqual(editor.presentation.selection.modelID, "gpt-5.5")
        XCTAssertEqual(
            editor.permissionOptions,
            [SettingsViewModel.pullRequestReviewInheritValue, "untrusted", "on-request", "never"]
        )
        // Every review task launches in a network-less sandbox, so its route never offers full access.
        XCTAssertEqual(editor.label(forPermission: "never"), "Never ask")
    }

    /// Addressing feedback keeps shell network to push, so its route still means full access.
    func testOnlyTheReviewRouteDescribesCodexNeverAsSandboxed() async {
        var settings = AppSettings()
        settings.pullRequestAddressFeedbackHarness = "codex"
        let (viewModel, _) = await reviewViewModel(settings: settings)

        XCTAssertEqual(viewModel.addressFeedbackAgentEditor.label(forPermission: "never"), "Full access")
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

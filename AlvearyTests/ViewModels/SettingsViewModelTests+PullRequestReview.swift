import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

/// The Git tab's agentic-review agent pickers: a leading "Default" row that persists as
/// nil, and the lockstep clearing that keeps a pinned model from outliving its provider.
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
            providerDiscovery: RecordingProviderDiscoveryService(statuses: [
                .claude: Self.providerStatus(for: .claude, modelOptions: AgentModelOptionTestFixtures.claudeModelOptions),
                .codex: Self.providerStatus(for: .codex, modelOptions: AgentModelOptionTestFixtures.codexModelOptions)
            ]),
            sidebarSectionOptionsLoader: { store.options }
        )
        await viewModel.refreshProviderStatuses()
        viewModel.refreshSidebarSectionOptions()
        return (viewModel, settingsService)
    }

    private static let sectionFixtures = [
        SettingsSidebarSectionOption(id: "section-a", name: "Reviews"),
        SettingsSidebarSectionOption(id: "section-b", name: "Fixes")
    ]

    func testUnpinnedReviewAgentSettingsSelectTheInheritRow() async {
        let (viewModel, _) = await reviewViewModel()

        XCTAssertEqual(viewModel.pullRequestReviewProviderSelection, SettingsViewModel.pullRequestReviewInheritValue)
        XCTAssertEqual(viewModel.pullRequestReviewModelSelection, SettingsViewModel.pullRequestReviewInheritValue)
        XCTAssertEqual(viewModel.pullRequestReviewEffortSelection, SettingsViewModel.pullRequestReviewInheritValue)
        XCTAssertEqual(viewModel.pullRequestReviewLabel(forProvider: SettingsViewModel.pullRequestReviewInheritValue), "Default")
    }

    func testTheInheritRowLeadsEveryPickerExactlyOnce() async {
        let (viewModel, _) = await reviewViewModel()

        XCTAssertEqual(viewModel.pullRequestReviewProviderOptions.first, SettingsViewModel.pullRequestReviewInheritValue)
        XCTAssertEqual(viewModel.pullRequestReviewModelOptions.first, SettingsViewModel.pullRequestReviewInheritValue)
        XCTAssertEqual(
            viewModel.pullRequestReviewModelOptions.filter { $0 == SettingsViewModel.pullRequestReviewInheritValue }.count,
            1
        )
    }

    func testPickingTheInheritRowClearsTheStoredValue() async {
        var settings = AppSettings()
        settings.pullRequestReviewProvider = "codex"
        let (viewModel, settingsService) = await reviewViewModel(settings: settings)

        viewModel.setPullRequestReviewProvider(SettingsViewModel.pullRequestReviewInheritValue)

        XCTAssertNil(settingsService.current.pullRequestReviewProvider)
    }

    func testPinningAProviderPersistsItAndClearsTheModelAndEffortInTheSameWrite() async {
        var settings = AppSettings()
        settings.pullRequestReviewModel = "sonnet"
        settings.pullRequestReviewEffort = "max"
        let (viewModel, settingsService) = await reviewViewModel(settings: settings)

        viewModel.setPullRequestReviewProvider("codex")

        XCTAssertEqual(settingsService.current.pullRequestReviewProvider, "codex")
        // A Claude model cannot survive onto Codex, and neither can an effort scoped to it.
        XCTAssertNil(settingsService.current.pullRequestReviewModel)
        XCTAssertNil(settingsService.current.pullRequestReviewEffort)
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

    func testTheReviewPromptPassesThroughToSettings() async {
        let (viewModel, settingsService) = await reviewViewModel()

        viewModel.pullRequestReviewPrompt = "Only look at the tests."

        XCTAssertEqual(settingsService.current.pullRequestReviewPrompt, "Only look at the tests.")
        XCTAssertEqual(viewModel.pullRequestReviewPrompt, "Only look at the tests.")
    }

    /// Model and effort options come from whichever provider the review will actually use, so a
    /// pinned provider must move them off the Threads default's catalog.
    func testAPinnedProviderSuppliesTheModelOptions() async {
        var settings = AppSettings()
        settings.pullRequestReviewProvider = "codex"
        let (viewModel, _) = await reviewViewModel(settings: settings)

        XCTAssertEqual(viewModel.pullRequestReviewEffectiveProviderID, "codex")
        XCTAssertTrue(viewModel.pullRequestReviewModelOptions.contains("gpt-5.5"))
        XCTAssertFalse(viewModel.pullRequestReviewModelOptions.contains("sonnet"))
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

import AgentCLIKit
import XCTest

@testable import Alveary

/// The Git tab's agentic-review agent pickers: a leading "Default" row that persists as
/// nil, and the lockstep clearing that keeps a pinned model from outliving its provider.
@MainActor
extension SettingsViewModelTests {
    private func reviewViewModel(
        settings: AppSettings = AppSettings()
    ) async -> (SettingsViewModel, InMemorySettingsService) {
        let settingsService = InMemorySettingsService(current: settings)
        let viewModel = SettingsViewModel(
            settingsService: settingsService,
            providerDiscovery: RecordingProviderDiscoveryService(statuses: [
                .claude: Self.providerStatus(for: .claude, modelOptions: AgentModelOptionTestFixtures.claudeModelOptions),
                .codex: Self.providerStatus(for: .codex, modelOptions: AgentModelOptionTestFixtures.codexModelOptions)
            ])
        )
        await viewModel.refreshProviderStatuses()
        return (viewModel, settingsService)
    }

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
}

import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
extension SettingsViewModelTests {
    func testUnavailableOpenCodeReviewPinsKeepTheirOwnHarnessEditor() async {
        var settings = AppSettings()
        settings.defaultHarness = "claude"
        settings.pullRequestReviewAgent = PullRequestAgentSettings(harness: "opencode", model: "provider/retired", effort: "native")
        settings.pullRequestAddressFeedbackAgent = settings.pullRequestReviewAgent
        let settingsService = InMemorySettingsService(current: settings)
        let viewModel = SettingsViewModel(
            settingsService: settingsService,
            harnessDiscovery: RecordingHarnessDiscoveryService(statuses: [
                .claude: Self.harnessStatus(for: .claude, modelOptions: AgentModelOptionTestFixtures.claudeModelOptions)
            ])
        )
        await viewModel.refreshHarnessStatuses()

        XCTAssertEqual(viewModel.pullRequestReviewEffectiveHarnessID, "opencode")
        XCTAssertEqual(viewModel.addressFeedbackEffectiveHarnessID, "opencode")
        XCTAssertFalse(viewModel.pullRequestReviewModelOptions.contains("sonnet"))
        XCTAssertFalse(viewModel.addressFeedbackPermissionOptions.contains("acceptEdits"))
        XCTAssertEqual(settingsService.current.pullRequestReviewAgent, settings.pullRequestReviewAgent)
    }

    func testOpenCodeReviewInheritedModelUsesThatModelsNativeVariants() {
        var settings = AppSettings()
        settings.defaultHarness = "opencode"
        settings.defaultModel = "provider/reasoning"
        let service = InMemorySettingsService(current: settings)
        let viewModel = SettingsViewModel(settingsService: service)
        viewModel.harnessStatuses["opencode"] = AgentHarnessStatus(
            harnessId: .opencode, definition: OpenCodeHarnessDefinition.definition,
            modelOptions: [
                AgentModelOption(harnessId: .opencode, id: "default", model: nil, label: "Default", isDefault: true),
                AgentModelOption(
                    harnessId: .opencode, id: "provider/reasoning", model: "provider/reasoning", label: "Reasoning",
                    supportedEffortOptions: [.init(value: "native", label: "Native", description: "")]
                )
            ]
        )
        XCTAssertTrue(viewModel.pullRequestReviewEffortOptions.contains { $0.value == "native" })
        XCTAssertTrue(viewModel.addressFeedbackEffortOptions.contains { $0.value == "native" })
    }

    func testExplicitOpenCodeReviewModelWithoutVariantsResetsEffortToConfiguredDefault() {
        var settings = AppSettings()
        settings.defaultHarness = "opencode"
        settings.effort = "inherited-native-variant"
        settings.pullRequestReviewAgent = PullRequestAgentSettings(harness: "opencode", effort: "saved-native-variant")
        let service = InMemorySettingsService(current: settings)
        let viewModel = SettingsViewModel(settingsService: service)
        viewModel.harnessStatuses["opencode"] = AgentHarnessStatus(
            harnessId: .opencode, definition: OpenCodeHarnessDefinition.definition,
            modelOptions: [AgentModelOption(harnessId: .opencode, id: "provider/text", model: "provider/text", label: "Text")]
        )

        viewModel.setPullRequestReviewModel("provider/text")
        viewModel.setAddressFeedbackModel("provider/text")

        XCTAssertEqual(service.current.pullRequestReviewEffort, AppSettings.openCodeDefaultEffort)
        XCTAssertEqual(service.current.pullRequestAddressFeedbackEffort, AppSettings.openCodeDefaultEffort)
        XCTAssertEqual(service.current.effort, "inherited-native-variant")
    }

}

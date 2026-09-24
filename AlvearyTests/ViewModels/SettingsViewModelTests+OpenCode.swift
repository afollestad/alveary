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

        for editor in [viewModel.reviewAgentEditor, viewModel.addressFeedbackAgentEditor] {
            XCTAssertEqual(editor.presentation.effective.harness.id, "opencode")
            XCTAssertTrue(editor.presentation.selection.effortOptions.isEmpty)
            XCTAssertFalse(editor.permissionOptions.contains("acceptEdits"))
        }
        XCTAssertEqual(settingsService.current.pullRequestReviewAgent, settings.pullRequestReviewAgent)
    }

    func testOpenCodeReviewInheritedModelUsesThatModelsNativeVariants() {
        var settings = AppSettings()
        settings.defaultHarness = "opencode"
        settings.defaultModel = "provider/reasoning"
        let service = InMemorySettingsService(current: settings)
        let viewModel = SettingsViewModel(settingsService: service)
        viewModel.harnessStatuses["opencode"] = Self.harnessStatus(
            for: .opencode,
            modelOptions: [
                AgentModelOption(harnessId: .opencode, id: "default", model: nil, label: "Default", isDefault: true),
                AgentModelOption(
                    harnessId: .opencode, id: "provider/reasoning", model: "provider/reasoning", label: "Reasoning",
                    supportedEffortOptions: [.init(value: "native", label: "Native", description: "")]
                )
            ]
        )
        for editor in [viewModel.reviewAgentEditor, viewModel.addressFeedbackAgentEditor] {
            XCTAssertTrue(editor.presentation.selection.effortOptions.contains { $0.value == "native" })
        }
    }

    func testExplicitOpenCodeReviewModelWithoutVariantsResetsEffortToConfiguredDefault() {
        var settings = AppSettings()
        settings.defaultHarness = "opencode"
        settings.effort = "inherited-native-variant"
        settings.pullRequestReviewAgent = PullRequestAgentSettings(harness: "opencode", effort: "saved-native-variant")
        let service = InMemorySettingsService(current: settings)
        let viewModel = SettingsViewModel(settingsService: service)
        viewModel.harnessStatuses["opencode"] = Self.harnessStatus(
            for: .opencode,
            modelOptions: [AgentModelOption(harnessId: .opencode, id: "provider/text", model: "provider/text", label: "Text")]
        )

        for editor in [viewModel.reviewAgentEditor, viewModel.addressFeedbackAgentEditor] {
            pickAgentModel("provider/text", harnessID: "opencode", in: editor.presentation) { editor.apply($0) }
        }

        XCTAssertEqual(service.current.pullRequestReviewEffort, AppSettings.openCodeDefaultEffort)
        XCTAssertEqual(service.current.pullRequestAddressFeedbackEffort, AppSettings.openCodeDefaultEffort)
        XCTAssertEqual(service.current.effort, "inherited-native-variant")
    }
}

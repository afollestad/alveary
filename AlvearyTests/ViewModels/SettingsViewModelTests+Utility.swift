import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension SettingsViewModelTests {
    func testUtilitySelectionPreservesUnavailableModelPinsAndRepairsOnlyOnExplicitChange() throws {
        var settings = AppSettings()
        settings.defaultHarness = "opencode"
        settings.utilityHarness = "opencode"
        settings.utilityModel = "provider/model"
        settings.utilityEffort = "variant"
        let service = InMemorySettingsService(current: settings)
        let viewModel = SettingsViewModel(settingsService: service)
        XCTAssertEqual(viewModel.utilityHarnessSelection, "opencode")
        XCTAssertTrue(viewModel.utilityHarnessOptions.contains("opencode"))
        XCTAssertNotNil(viewModel.utilityUnavailableMessage)
        XCTAssertTrue(viewModel.canConfigureUtilityModel)
        XCTAssertEqual(service.updateCount, 0)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(service.current))
        XCTAssertEqual(decoded.utilityHarness, "opencode")
        XCTAssertEqual(decoded.utilityModel, "provider/model")
        XCTAssertEqual(decoded.utilityEffort, "variant")

        viewModel.setUtilityHarness("claude")
        XCTAssertEqual(service.current.utilityHarness, "claude")
        XCTAssertNil(service.current.utilityModel)
        XCTAssertNil(service.current.utilityEffort)
        XCTAssertEqual(service.current.effectiveUtilityModel, "default")
        XCTAssertNil(viewModel.utilityUnavailableMessage)
        XCTAssertEqual(service.current.defaultHarness, "opencode")
    }

    func testCreatingReviewPeersPreservesInvalidSavedLeadWithoutFallback() {
        var settings = AppSettings()
        settings.pullRequestReviewHarness = "claude"
        settings.pullRequestReviewModel = "retired-model"
        settings.pullRequestReviewEffort = "retired-effort"
        let service = InMemorySettingsService(current: settings)
        let viewModel = SettingsViewModel(settingsService: service)
        let draft = viewModel.reviewTeamEditorSettings()
        XCTAssertEqual(draft.pullRequestReviewHarness, "claude")
        XCTAssertEqual(draft.pullRequestReviewModel, "retired-model")
        XCTAssertEqual(draft.pullRequestReviewEffort, "retired-effort")
        XCTAssertEqual(service.updateCount, 0)
    }

    func testOpenCodeInheritedUtilityRequiresConcreteModelAndReviewLeadStaysInherited() {
        var settings = AppSettings()
        settings.defaultHarness = "opencode"
        let service = InMemorySettingsService(current: settings)
        let viewModel = SettingsViewModel(settingsService: service)
        XCTAssertEqual(viewModel.utilityHarnessID, "opencode")
        XCTAssertNotNil(viewModel.utilityUnavailableMessage)
        XCTAssertTrue(viewModel.utilityHarnessOptions.contains(SettingsViewModel.pullRequestReviewInheritValue))
        XCTAssertEqual(viewModel.reviewTeamEditorSettings().defaultHarness, "opencode")
        XCTAssertNil(viewModel.reviewTeamEditorSettings().pullRequestReviewHarness)
        XCTAssertTrue(viewModel.reviewTeamLeadHarnessOptions(settings).contains("opencode"))
        XCTAssertTrue(viewModel.reviewTeamLeadHarnessOptions(settings).contains(SettingsViewModel.pullRequestReviewInheritValue))
        XCTAssertNil(viewModel.defaultPullRequestReviewPeer(harnessID: "opencode", excluding: []))
        XCTAssertEqual(service.updateCount, 0)
    }

    func testOpenCodeUtilityModelChangeUsesNativeDefaultInsteadOfInheritedVariant() {
        var settings = AppSettings()
        settings.defaultHarness = "opencode"
        settings.defaultModel = "provider/reasoning"
        settings.effort = "native"
        let service = InMemorySettingsService(current: settings)
        let viewModel = SettingsViewModel(settingsService: service)
        viewModel.harnessStatuses["opencode"] = Self.harnessStatus(for: .opencode, modelOptions: [
            AgentModelOption(harnessId: .opencode, id: "default", model: nil, label: "Default", isDefault: true),
            AgentModelOption(harnessId: .opencode, id: "provider/text", model: "provider/text", label: "Text")
        ])

        viewModel.setUtilityModel("provider/text")

        XCTAssertEqual(service.current.effectiveUtilityEffort, AppSettings.openCodeDefaultEffort)
        XCTAssertNil(viewModel.utilityUnavailableMessage)
        XCTAssertFalse(viewModel.utilityModelOptions.contains("default"))
        XCTAssertEqual(service.current.effort, "native")
        service.update { $0.utilityEffort = "retired" }
        XCTAssertNotNil(viewModel.utilityUnavailableMessage)
        XCTAssertTrue(viewModel.utilityEffortOptions.contains("retired"))
        XCTAssertTrue(viewModel.utilityEffortOptions.contains(AppSettings.openCodeDefaultEffort))
        XCTAssertEqual(viewModel.utilityEffortLabel(SettingsViewModel.pullRequestReviewInheritValue), "Follow defaults")
        XCTAssertEqual(viewModel.utilityEffortLabel(AppSettings.openCodeDefaultEffort), "Default")
        viewModel.setUtilityEffort(AppSettings.openCodeDefaultEffort)
        XCTAssertNil(viewModel.utilityUnavailableMessage)
    }

    func testNativeInheritVariantStaysDistinctFromUtilityAndReviewInheritance() throws {
        let native = AppSettings.inheritedSelectionValue
        var settings = AppSettings()
        settings.defaultHarness = "opencode"
        settings.defaultModel = "provider/model"
        settings.effort = native
        settings.utilityEffort = native
        settings.pullRequestAddressFeedbackEffort = native
        let service = InMemorySettingsService(current: settings)
        let original = service.current
        let viewModel = SettingsViewModel(settingsService: service)
        viewModel.harnessStatuses["opencode"] = Self.harnessStatus(for: .opencode, modelOptions: [
            AgentModelOption(
                harnessId: .opencode, id: "provider/model", model: "provider/model", label: "Model",
                supportedEffortOptions: [.init(value: native, label: native, description: "Native variant")]
            )
        ])
        let utilityOptions = viewModel.utilityEffortOptions
        XCTAssertEqual(Set(utilityOptions).count, utilityOptions.count)
        let selection = try XCTUnwrap(utilityOptions.first { viewModel.utilityEffortLabel($0) == native })
        XCTAssertEqual(viewModel.utilityEffortSelection, selection)
        XCTAssertEqual(viewModel.addressFeedbackEffortSelection, selection)
        XCTAssertEqual(viewModel.effort, selection)
        XCTAssertEqual(service.current, original)
        viewModel.setUtilityEffort(selection)
        XCTAssertEqual(AppSettings.openCodeNativeEffort(stored: service.current.utilityEffort), native)
        XCTAssertNil(viewModel.utilityUnavailableMessage)

        var draft = settings
        let leadOptions = viewModel.reviewTeamLeadEffortOptions(draft)
        XCTAssertEqual(Set(leadOptions).count, leadOptions.count)
        XCTAssertTrue(leadOptions.contains(selection))
        XCTAssertEqual(viewModel.reviewTeamLeadEffortSelection(draft), SettingsViewModel.pullRequestReviewInheritValue)
        XCTAssertEqual(viewModel.pullRequestReviewPeerEffortSelection(viewModel.reviewTeamDraftLead(draft)), selection)
        draft.pullRequestReviewEffort = native
        XCTAssertEqual(viewModel.reviewTeamLeadEffortSelection(draft), selection)
        XCTAssertEqual(draft.pullRequestReviewEffort, native)
        viewModel.setReviewTeamLeadEffort(selection, in: &draft)
        viewModel.setPullRequestReviewTeam(draft)
        XCTAssertEqual(AppSettings.openCodeNativeEffort(stored: service.current.pullRequestReviewEffort), native)
        viewModel.setAddressFeedbackEffort(selection)
        XCTAssertEqual(AppSettings.openCodeNativeEffort(stored: service.current.pullRequestAddressFeedbackEffort), native)
        XCTAssertEqual(viewModel.pullRequestReviewLabel(forEffort: SettingsViewModel.pullRequestReviewInheritValue), "Follow defaults")
        XCTAssertEqual(viewModel.addressFeedbackLabel(forEffort: SettingsViewModel.pullRequestReviewInheritValue), "Follow defaults")
        XCTAssertEqual(viewModel.pullRequestReviewLabel(forEffort: AppSettings.openCodeDefaultEffort), "Default")
        XCTAssertEqual(viewModel.addressFeedbackLabel(forEffort: selection), native)

        viewModel.setUtilityEffort(SettingsViewModel.pullRequestReviewInheritValue)
        viewModel.setReviewTeamLeadEffort(SettingsViewModel.pullRequestReviewInheritValue, in: &draft)
        XCTAssertNil(service.current.utilityEffort)
        XCTAssertNil(draft.pullRequestReviewEffort)
    }
}

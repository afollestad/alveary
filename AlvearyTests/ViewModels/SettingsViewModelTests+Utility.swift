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
        let presentation = viewModel.utilityAgentPresentation
        XCTAssertEqual(presentation.pins, .init(harnessID: "opencode", model: "provider/model", effort: "variant"))
        XCTAssertEqual(presentation.effective.harness.id, "opencode")
        XCTAssertTrue(presentation.selection.effortOptions.isEmpty)
        XCTAssertNotNil(viewModel.utilityUnavailableMessage)
        XCTAssertEqual(service.updateCount, 0)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(service.current))
        XCTAssertEqual(decoded.utilityHarness, "opencode")
        XCTAssertEqual(decoded.utilityModel, "provider/model")
        XCTAssertEqual(decoded.utilityEffort, "variant")

        pickAgentModel("opus", harnessID: "claude", in: presentation) { viewModel.applyUtilityAgent($0) }
        XCTAssertEqual(service.current.utilityHarness, "claude")
        XCTAssertEqual(service.current.utilityModel, "claude-opus-5-5")
        XCTAssertEqual(service.current.utilityEffort, "medium")
        XCTAssertNil(viewModel.utilityUnavailableMessage)
        XCTAssertEqual(service.current.defaultHarness, "opencode")

        pickAgentInherit(in: viewModel.utilityAgentPresentation) { viewModel.applyUtilityAgent($0) }
        XCTAssertNil(service.current.utilityHarness)
        XCTAssertNil(service.current.utilityModel)
        XCTAssertNil(service.current.utilityEffort)
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
        XCTAssertEqual(viewModel.utilityAgentPresentation.inheritOption?.isSelected, true)
        XCTAssertEqual(viewModel.reviewTeamEditorSettings().defaultHarness, "opencode")
        XCTAssertNil(viewModel.reviewTeamEditorSettings().pullRequestReviewHarness)
        let lead = viewModel.reviewTeamLeadPresentation(settings)
        XCTAssertEqual(lead.effective.harness.id, "opencode")
        XCTAssertEqual(lead.inheritOption?.isSelected, true)
        XCTAssertEqual(lead.inheritOption?.isEnabled, true)
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

        pickAgentModel("provider/text", harnessID: "opencode", in: viewModel.utilityAgentPresentation) { viewModel.applyUtilityAgent($0) }

        XCTAssertEqual(service.current.effectiveUtilityEffort, AppSettings.openCodeDefaultEffort)
        XCTAssertNil(viewModel.utilityUnavailableMessage)
        let openCodeGroup = viewModel.utilityAgentPresentation.modelGroups.first { $0.harnessID == "opencode" }
        XCTAssertEqual(openCodeGroup?.options.map(\.value), ["provider/text"])
        XCTAssertEqual(service.current.effort, "native")
        service.update { $0.utilityEffort = "retired" }
        XCTAssertNotNil(viewModel.utilityUnavailableMessage)
        // A variant-less model offers no effort slider, so re-picking it is the repair.
        XCTAssertTrue(viewModel.utilityAgentPresentation.selection.effortOptions.isEmpty)
        pickAgentModel("provider/text", harnessID: "opencode", in: viewModel.utilityAgentPresentation) { viewModel.applyUtilityAgent($0) }
        XCTAssertEqual(service.current.utilityEffort, AppSettings.openCodeDefaultEffort)
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
        let utilityOptions = viewModel.utilityAgentPresentation.selection.effortOptions
        XCTAssertEqual(Set(utilityOptions.map(\.value)).count, utilityOptions.count)
        let selection = try XCTUnwrap(utilityOptions.first { $0.title == native }?.value)
        XCTAssertEqual(viewModel.utilityAgentPresentation.selection.effortValue, selection)
        XCTAssertEqual(viewModel.addressFeedbackAgentEditor.presentation.selection.effortValue, selection)
        XCTAssertEqual(viewModel.threadDefaultAgentPresentation.selection.effortValue, selection)
        XCTAssertEqual(service.current, original)
        dragAgentEffort(selection, in: viewModel.utilityAgentPresentation) { viewModel.applyUtilityAgent($0) }
        XCTAssertEqual(AppSettings.openCodeNativeEffort(stored: service.current.utilityEffort), native)
        XCTAssertNil(viewModel.utilityUnavailableMessage)

        var draft = settings
        let lead = viewModel.reviewTeamLeadPresentation(draft)
        XCTAssertEqual(Set(lead.selection.effortOptions.map(\.value)).count, lead.selection.effortOptions.count)
        XCTAssertTrue(lead.isInherited)
        XCTAssertEqual(lead.selection.effortValue, selection)
        draft.pullRequestReviewEffort = native
        XCTAssertEqual(viewModel.reviewTeamLeadPresentation(draft).selection.effortValue, selection)
        XCTAssertEqual(draft.pullRequestReviewEffort, native)
        dragAgentEffort(selection, in: viewModel.reviewTeamLeadPresentation(draft)) { viewModel.applyReviewTeamLead($0, in: &draft) }
        viewModel.setPullRequestReviewTeam(draft)
        XCTAssertEqual(AppSettings.openCodeNativeEffort(stored: service.current.pullRequestReviewEffort), native)
        let feedback = viewModel.addressFeedbackAgentEditor
        dragAgentEffort(selection, in: feedback.presentation) { feedback.apply($0) }
        XCTAssertEqual(AppSettings.openCodeNativeEffort(stored: service.current.pullRequestAddressFeedbackEffort), native)

        pickAgentInherit(in: viewModel.utilityAgentPresentation) { viewModel.applyUtilityAgent($0) }
        pickAgentInherit(in: viewModel.reviewTeamLeadPresentation(draft)) { viewModel.applyReviewTeamLead($0, in: &draft) }
        XCTAssertNil(service.current.utilityEffort)
        XCTAssertNil(draft.pullRequestReviewEffort)
    }
}

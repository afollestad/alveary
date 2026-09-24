import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
final class AgentReasoningPresentationTests: XCTestCase {
    func testGroupsEveryOfferedHarnessAndRepairsAnUnknownEffectiveModel() {
        let presentation = makeAgentReasoningPresentation(
            harnesses: [.testClaude, .testCodex, .testEmptyOpenCode],
            effective: .init(harness: .testClaude, model: "claude-retired", effort: "high")
        )

        XCTAssertEqual(presentation.modelGroups.map(\.harnessID), ["claude", "codex"])
        XCTAssertEqual(presentation.modelGroups.map(\.harnessTitle), ["Claude", "Codex"])
        XCTAssertEqual(presentation.modelGroups.first?.options.map(\.value), ["claude-opus-5-5", "claude-haiku", "claude-retired"])
        XCTAssertTrue(presentation.selection.effortOptions.isEmpty)
    }

    func testAnEmptyEffectiveCatalogListsOnlyTheRepairRow() {
        let presentation = makeAgentReasoningPresentation(
            harnesses: [.testClaude, .testEmptyOpenCode],
            effective: .init(harness: .testEmptyOpenCode, model: "provider/gone", effort: AppSettings.openCodeDefaultEffort)
        )

        XCTAssertEqual(presentation.modelGroups.last?.options.map(\.value), ["provider/gone"])
        XCTAssertNil(presentation.pins(for: .init(harnessID: "opencode", modelID: AppSettings.defaultModelValue)))
    }

    func testEffortHidesWhenTheEffectiveHarnessIsNotOffered() {
        let presentation = makeAgentReasoningPresentation(
            harnesses: [.testCodex],
            effective: .init(harness: .testClaude, model: "claude-opus-5-5", effort: "high")
        )

        XCTAssertEqual(presentation.modelGroups.map(\.harnessID), ["codex"])
        XCTAssertTrue(presentation.selection.effortOptions.isEmpty)
        XCTAssertEqual(presentation.buttonTitle, "Claude · Opus 5.5")
    }

    func testInheritRowTracksOfferAndStoredInheritance() {
        let offered = makeAgentReasoningPresentation(
            pins: .inherited,
            effective: .init(harness: .testCodex, model: "gpt-6-astra", effort: "medium"),
            inheritance: makeAgentReasoningInheritance(isOffered: true)
        )
        XCTAssertEqual(offered.inheritOption, .init(
            title: "Threads default",
            detail: "Codex · GPT-6-Astra · Medium",
            isSelected: true,
            isEnabled: true
        ))
        XCTAssertEqual(offered.buttonTitle, "Default (Codex · GPT-6-Astra)")

        let repair = makeAgentReasoningPresentation(pins: .inherited, inheritance: makeAgentReasoningInheritance(isOffered: false))
        XCTAssertEqual(repair.inheritOption?.isSelected, true)
        XCTAssertEqual(repair.inheritOption?.isEnabled, false)

        XCTAssertNil(makeAgentReasoningPresentation(inheritance: makeAgentReasoningInheritance(isOffered: false)).inheritOption)
        XCTAssertNil(makeAgentReasoningPresentation(pins: .inherited).inheritOption)
    }

    func testPartialPinDisplaysEffectiveSelectionWithoutInheriting() {
        let presentation = makeAgentReasoningPresentation(
            pins: .init(harnessID: "claude"),
            effective: .init(harness: .testClaude, model: "claude-opus-5-5", effort: "high"),
            inheritance: makeAgentReasoningInheritance(isOffered: true)
        )

        XCTAssertFalse(presentation.isInherited)
        XCTAssertEqual(presentation.inheritOption?.isSelected, false)
        XCTAssertEqual(presentation.buttonTitle, "Claude · Opus 5.5")
        XCTAssertEqual(presentation.selection.effortTitle, "High")
        XCTAssertEqual(presentation.pins(for: .init(harnessID: "claude", modelID: "claude-opus-5-5")), presentation.pins)
    }

    func testModelPickKeepsSupportedEffortAndOtherwiseFallsToModelDefault() {
        let presentation = makeAgentReasoningPresentation(effective: .init(harness: .testClaude, model: "claude-opus-5-5", effort: "medium"))

        XCTAssertEqual(
            presentation.pins(for: .init(harnessID: "claude", modelID: "claude-haiku")),
            .init(harnessID: "claude", model: "claude-haiku", effort: "medium")
        )
        XCTAssertEqual(presentation.pins(forEffort: "max").effort, "max")
        let maxPresentation = makeAgentReasoningPresentation(effective: .init(harness: .testClaude, model: "claude-opus-5-5", effort: "max"))
        XCTAssertEqual(
            maxPresentation.pins(for: .init(harnessID: "claude", modelID: "claude-haiku")),
            .init(harnessID: "claude", model: "claude-haiku", effort: "low")
        )
        XCTAssertNil(presentation.pins(for: .init(harnessID: "claude", modelID: "claude-unlisted")))
        XCTAssertNil(presentation.pins(for: .init(harnessID: "opencode", modelID: "provider/model")))
    }

    func testRePickingTheCheckedRowRepairsAnEffortTheModelDropped() {
        let presentation = makeAgentReasoningPresentation(
            pins: .init(harnessID: "claude", model: "claude-haiku", effort: "max"),
            effective: .init(harness: .testClaude, model: "claude-haiku", effort: "max")
        )

        XCTAssertEqual(
            presentation.pins(for: .init(harnessID: "claude", modelID: "claude-haiku")),
            .init(harnessID: "claude", model: "claude-haiku", effort: "low")
        )
    }

    func testModelPickAcrossHarnessesDropsEffortTheNewModelCannotCheck() {
        let noEffortHarness = AgentReasoningPresentation.Harness(
            id: "codex",
            title: "Codex",
            modelOptions: [AgentModelOption(harnessId: .codex, id: "plain", model: "plain", label: "Plain")]
        )
        let presentation = makeAgentReasoningPresentation(
            harnesses: [.testOpenCode, noEffortHarness],
            effective: .init(harness: .testOpenCode, model: "provider/model", effort: AppSettings.openCodeDefaultEffort)
        )

        XCTAssertEqual(
            presentation.pins(for: .init(harnessID: "codex", modelID: "plain"))?.effort,
            AppSettings.defaultEffortLevel
        )
    }

    func testOpenCodeModelPickFallsToConfiguredDefaultForUnsupportedVariant() {
        let presentation = makeAgentReasoningPresentation(
            harnesses: [.testOpenCode],
            effective: .init(harness: .testOpenCode, model: "provider/model", effort: "deep")
        )

        XCTAssertEqual(presentation.selection.effortValue, "deep")
        XCTAssertEqual(
            presentation.pins(for: .init(harnessID: "opencode", modelID: "provider/other"))?.effort,
            AppSettings.openCodeDefaultEffort
        )
    }

    /// The configured-default fallback would otherwise check a concrete model the host rejects.
    func testConcreteOnlyHarnessRepairsAStoredConfiguredDefault() {
        var openCode = AgentReasoningPresentation.Harness.testOpenCode
        openCode.requiresConcreteModel = true
        let pins = AgentReasoningPins(harnessID: "opencode", model: AppSettings.defaultModelValue, effort: AppSettings.openCodeDefaultEffort)
        let presentation = makeAgentReasoningPresentation(
            harnesses: [openCode],
            pins: pins,
            effective: .init(harness: openCode, model: AppSettings.defaultModelValue, effort: AppSettings.openCodeDefaultEffort)
        )

        XCTAssertEqual(presentation.selection.modelID, AppSettings.defaultModelValue)
        XCTAssertTrue(presentation.selection.effortOptions.isEmpty)
        XCTAssertEqual(
            presentation.modelGroups.first?.options.map(\.value),
            ["provider/model", "provider/other", AppSettings.defaultModelValue]
        )
        XCTAssertEqual(presentation.pins(for: .init(harnessID: "opencode", modelID: AppSettings.defaultModelValue)), pins)
        XCTAssertEqual(presentation.pins(for: .init(harnessID: "opencode", modelID: "provider/model"))?.model, "provider/model")
    }

    func testAvailabilityDrivesButtonTitle() {
        var checking = makeAgentReasoningPresentation()
        checking.isChecking = true
        XCTAssertEqual(checking.availability, .checking)
        XCTAssertEqual(checking.buttonTitle, "Checking harnesses…")

        let unavailable = makeAgentReasoningPresentation(harnesses: [])
        XCTAssertEqual(unavailable.availability, .unavailable)
        XCTAssertEqual(unavailable.buttonTitle, "No ready harnesses")
    }

    func testConfigurationAppliesOnlyChangedPinsAndReportsTheNextSelection() {
        var applied: [AgentReasoningPins] = []
        let presentation = makeAgentReasoningPresentation(
            pins: .init(harnessID: "claude", model: "claude-opus-5-5", effort: "high"),
            effective: .init(harness: .testClaude, model: "claude-opus-5-5", effort: "high"),
            inheritance: makeAgentReasoningInheritance(isOffered: true)
        )
        let configuration = ReasoningConfiguration(presentation: presentation) { pins in
            applied.append(pins)
            return true
        }

        guard case .unchanged = configuration.onModelChange(.init(harnessID: "claude", modelID: "claude-opus-5-5")) else {
            return XCTFail("Re-picking the pinned model should not write.")
        }
        guard case .applied(let selection) = configuration.onModelChange(.init(harnessID: "codex", modelID: "gpt-6-astra")) else {
            return XCTFail("Picking another harness's model should apply.")
        }
        XCTAssertEqual(selection.harnessID, "codex")
        guard case .applied(let inherited) = configuration.inheritChoice?.onSelect() else {
            return XCTFail("Picking the inherit row should apply.")
        }
        XCTAssertEqual(inherited.modelID, "gpt-6-astra")
        XCTAssertTrue(configuration.onEffortChange("max"))
        XCTAssertFalse(configuration.onSpeedChange(.fast))
        XCTAssertEqual(applied, [
            .init(harnessID: "codex", model: "gpt-6-astra", effort: "high"),
            .inherited,
            .init(harnessID: "claude", model: "claude-opus-5-5", effort: "max")
        ])
    }

    func testConfigurationRejectsHostRefusalAndDisabledInheritRow() {
        let refused = ReasoningConfiguration(
            presentation: makeAgentReasoningPresentation(inheritance: makeAgentReasoningInheritance(isOffered: true))
        ) { _ in false }
        guard case .rejected = refused.onModelChange(.init(harnessID: "claude", modelID: "claude-haiku")) else {
            return XCTFail("A refused write should reject.")
        }

        let repair = ReasoningConfiguration(
            presentation: makeAgentReasoningPresentation(pins: .inherited, inheritance: makeAgentReasoningInheritance(isOffered: false))
        ) { _ in true }
        guard case .rejected = repair.inheritChoice?.onSelect() else {
            return XCTFail("A disabled inherit row should reject.")
        }
    }
}

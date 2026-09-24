import AgentCLIKit
import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerActionRowTests {
    /// Guards the seam `/model` depends on: a harness alias has to survive
    /// `AgentModelOption` -> `AgentModelOptionMenuItem` -> `ReasoningModelOption`.
    /// Only an option whose alias differs from its id catches a dropped hop, which both harnesses now report.
    func testHarnessShortNamesReachMenuItems() {
        let options = [
            AgentCLIKit.AgentModelOption(
                harnessId: .codex,
                id: "gpt-5.6-sol",
                model: "gpt-5.6-sol",
                label: "GPT-5.6-Sol",
                shortName: "sol"
            ),
            AgentCLIKit.AgentModelOption(
                harnessId: .codex,
                id: "gpt-5.5",
                model: "gpt-5.5",
                label: "GPT-5.5"
            )
        ]

        let menuItems = AgentModelOptionSelection.menuItems(
            in: options,
            selectedModel: "gpt-5.6-sol",
            fallbackTitle: ChatComposerTextSupport.modelLabel(for:)
        )

        XCTAssertEqual(menuItems.map(\.value), ["gpt-5.6-sol", "gpt-5.5"])
        XCTAssertEqual(menuItems.map(\.shortName), ["sol", "gpt-5.5"])
    }

    func testSynthesizedMenuItemFallsBackToItsValueAsShortName() {
        let menuItems = AgentModelOptionSelection.menuItems(
            in: [],
            selectedModel: "gpt-5.6-sol",
            fallbackTitle: ChatComposerTextSupport.modelLabel(for:)
        )

        XCTAssertEqual(menuItems.map(\.shortName), menuItems.map(\.value))
    }

    /// Claude lists pinned version ids, so its family aliases only reach `/model` through this same seam.
    func testClaudeFamilyAliasesReachMenuItems() {
        let options = [
            AgentCLIKit.AgentModelOption(
                harnessId: .claude,
                id: "claude-opus-5-5",
                model: "claude-opus-5-5",
                label: "Opus 5.5",
                shortName: "opus"
            ),
            AgentCLIKit.AgentModelOption(
                harnessId: .claude,
                id: "claude-opus-5",
                model: "claude-opus-5",
                label: "Opus 5"
            )
        ]

        let menuItems = AgentModelOptionSelection.menuItems(
            in: options,
            selectedModel: "claude-opus-5-5",
            fallbackTitle: ChatComposerTextSupport.modelLabel(for:)
        )

        XCTAssertEqual(menuItems.map(\.value), ["claude-opus-5-5", "claude-opus-5"])
        XCTAssertEqual(menuItems.map(\.shortName), ["opus", "claude-opus-5"])
    }

    func testReasoningModelOptionDefaultsShortNameToItsValue() {
        let option = ReasoningModelOption(
            harnessID: "claude",
            value: "opus",
            title: "Opus"
        )

        XCTAssertEqual(option.shortName, "opus")
    }
}

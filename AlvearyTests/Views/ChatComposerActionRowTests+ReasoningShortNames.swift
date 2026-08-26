import AgentCLIKit
import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerActionRowTests {
    /// Guards the seam `/model` depends on: a provider alias has to survive
    /// `AgentModelOption` -> `AgentModelOptionMenuItem` -> `ReasoningModelOption`.
    /// Only an option whose alias differs from its id catches a dropped hop, which both providers now report.
    func testProviderShortNamesReachMenuItems() {
        let options = [
            AgentCLIKit.AgentModelOption(
                providerId: .codex,
                id: "gpt-5.6-sol",
                model: "gpt-5.6-sol",
                label: "GPT-5.6-Sol",
                shortName: "sol"
            ),
            AgentCLIKit.AgentModelOption(
                providerId: .codex,
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
                providerId: .claude,
                id: "claude-opus-5",
                model: "claude-opus-5",
                label: "Opus 5",
                shortName: "opus"
            ),
            AgentCLIKit.AgentModelOption(
                providerId: .claude,
                id: "claude-opus-4-8",
                model: "claude-opus-4-8",
                label: "Opus 4.8"
            )
        ]

        let menuItems = AgentModelOptionSelection.menuItems(
            in: options,
            selectedModel: "claude-opus-5",
            fallbackTitle: ChatComposerTextSupport.modelLabel(for:)
        )

        XCTAssertEqual(menuItems.map(\.value), ["claude-opus-5", "claude-opus-4-8"])
        XCTAssertEqual(menuItems.map(\.shortName), ["opus", "claude-opus-4-8"])
    }

    func testReasoningModelOptionDefaultsShortNameToItsValue() {
        let option = ChatComposerActionRowView.ReasoningModelOption(
            providerID: "claude",
            value: "opus",
            title: "Opus"
        )

        XCTAssertEqual(option.shortName, "opus")
    }
}

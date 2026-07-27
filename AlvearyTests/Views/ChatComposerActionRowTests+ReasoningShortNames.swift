import AgentCLIKit
import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerActionRowTests {
    /// Guards the seam `/model` depends on: a provider alias has to survive
    /// `AgentModelOption` -> `AgentModelOptionMenuItem` -> `ReasoningModelOption`.
    /// Claude aliases equal their ids, so only a Codex-shaped option catches a dropped hop.
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

    func testReasoningModelOptionDefaultsShortNameToItsValue() {
        let option = ChatComposerActionRowView.ReasoningModelOption(
            providerID: "claude",
            value: "opus",
            title: "Opus"
        )

        XCTAssertEqual(option.shortName, "opus")
    }
}

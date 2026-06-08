import XCTest

@testable import Alveary

@MainActor
extension ChatComposerActionRowTests {
    func testReasoningModelOptionsUseCodexProviderStatusLabelsAndEfforts() {
        let menuItems = AgentModelOptionSelection.menuItems(
            in: AgentModelOptionTestFixtures.codexModelOptions,
            selectedModel: "gpt-5.4-mini",
            fallbackTitle: ChatComposerTextSupport.modelLabel(for:)
        )
        let effortOptions = AgentModelOptionSelection.effortOptions(
            in: AgentModelOptionTestFixtures.codexModelOptions,
            selectedModel: "gpt-5.4-mini"
        )

        XCTAssertEqual(menuItems.map(\.value), ["gpt-5.5", "gpt-5.4-mini"])
        XCTAssertEqual(menuItems.map(\.title), ["GPT-5.5", "GPT-5.4-Mini"])
        XCTAssertEqual(effortOptions.map(\.value), ["low", "medium"])
    }
}

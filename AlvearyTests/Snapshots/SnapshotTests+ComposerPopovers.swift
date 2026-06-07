@preconcurrency import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testComposerReasoningMenuCompactContent() {
        let configuration = makeSnapshotReasoningMenuConfiguration()
        let size = ComposerReasoningMenuMetrics.mainContentSize(for: configuration)

        assertMacSnapshot(
            ComposerReasoningMenuSnapshot(configuration: configuration),
            size: size,
            named: "composer_reasoning_menu_compact_content",
            colorScheme: .dark
        )
    }

    func testComposerReasoningModelMenuGroupedContent() {
        let groups = makeGroupedReasoningModelGroups()
        let size = ComposerReasoningMenuMetrics.modelContentSize(groups: groups, showsProviderHeaders: true)

        assertMacSnapshot(
            ComposerReasoningModelMenuSnapshot(),
            size: size,
            named: "composer_reasoning_model_menu_grouped_content",
            colorScheme: .dark
        )
    }
}

@MainActor
private func makeSnapshotReasoningMenuConfiguration() -> ChatComposerActionRowView.ReasoningConfiguration {
    makeReasoningConfiguration(
        modelOptions: [.init(value: "gpt-5.3-codex-spark", title: "GPT-5.3-Codex-Spark")],
        effortOptions: [
            .init(value: "low", title: "Low"),
            .init(value: "medium", title: "Medium"),
            .init(value: "high", title: "High"),
            .init(value: "extra-high", title: "Extra High")
        ],
        selectedModel: "gpt-5.3-codex-spark",
        selectedEffort: "medium"
    )
}

private struct ComposerReasoningMenuSnapshot: NSViewControllerRepresentable {
    let configuration: ChatComposerActionRowView.ReasoningConfiguration

    func makeNSViewController(context: Context) -> ComposerReasoningMenuViewController {
        ComposerReasoningMenuViewController(configuration: configuration, onRequestCloseMainMenu: {})
    }

    func updateNSViewController(_ controller: ComposerReasoningMenuViewController, context: Context) {}
}

private struct ComposerReasoningModelMenuSnapshot: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> ComposerReasoningModelMenuViewController {
        makeGroupedReasoningModelMenu()
    }

    func updateNSViewController(_ controller: ComposerReasoningModelMenuViewController, context: Context) {}
}

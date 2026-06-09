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

    func testComposerReasoningMenuSpeedContent() {
        let configuration = makeSnapshotReasoningMenuConfiguration(
            selectedSpeedMode: .fast,
            supportsSpeedMode: true
        )
        let size = ComposerReasoningMenuMetrics.mainContentSize(for: configuration)

        assertMacSnapshot(
            ComposerReasoningMenuSnapshot(configuration: configuration),
            size: size,
            named: "composer_reasoning_menu_speed_content",
            colorScheme: .dark
        )
    }

    func testComposerReasoningSpeedMenuContent() {
        let size = ComposerReasoningMenuMetrics.speedContentSize()

        assertMacSnapshot(
            ComposerReasoningSpeedMenuSnapshot(selectedSpeedMode: .fast),
            size: size,
            named: "composer_reasoning_speed_menu_content",
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

    func testComposerPermissionMenuCodexContent() {
        let options = makeSnapshotPermissionOptions()
        let size = ComposerPermissionMenuMetrics.contentSize(optionCount: options.count)

        assertMacSnapshot(
            ComposerPermissionMenuSnapshot(options: options),
            size: size,
            named: "composer_permission_menu_codex_content",
            colorScheme: .dark
        )
    }

    func testComposerWorktreeLocationMenuContent() {
        let options = ChatComposerWorktreeLocationPresentation.options()
        let size = ComposerWorktreeMenuMetrics.contentSize(optionCount: options.count)

        assertMacSnapshot(
            ComposerWorktreeLocationMenuSnapshot(options: options),
            size: size,
            named: "composer_worktree_location_menu_content",
            colorScheme: .dark
        )
    }
}

@MainActor
private func makeSnapshotReasoningMenuConfiguration(
    selectedSpeedMode: AgentSpeedMode = .standard,
    supportsSpeedMode: Bool = false
) -> ChatComposerActionRowView.ReasoningConfiguration {
    makeReasoningConfiguration(
        modelOptions: [.init(value: "gpt-5.3-codex-spark", title: "GPT-5.3-Codex-Spark")],
        effortOptions: [
            .init(value: "low", title: "Low"),
            .init(value: "medium", title: "Medium"),
            .init(value: "high", title: "High"),
            .init(value: "extra-high", title: "Extra High")
        ],
        selectedModel: "gpt-5.3-codex-spark",
        selectedEffort: "medium",
        selectedSpeedMode: selectedSpeedMode,
        supportsSpeedMode: supportsSpeedMode
    )
}

private struct ComposerReasoningMenuSnapshot: NSViewControllerRepresentable {
    let configuration: ChatComposerActionRowView.ReasoningConfiguration

    func makeNSViewController(context: Context) -> ComposerReasoningMenuViewController {
        ComposerReasoningMenuViewController(configuration: configuration, onRequestCloseMainMenu: {})
    }

    func updateNSViewController(_ controller: ComposerReasoningMenuViewController, context: Context) {}
}

private struct ComposerReasoningSpeedMenuSnapshot: NSViewControllerRepresentable {
    let selectedSpeedMode: AgentSpeedMode

    func makeNSViewController(context: Context) -> ComposerReasoningSpeedMenuViewController {
        ComposerReasoningSpeedMenuViewController(
            selectedSpeedMode: selectedSpeedMode,
            onSpeedSelected: { _ in },
            onHoverChanged: { _ in },
            onCancel: {}
        )
    }

    func updateNSViewController(_ controller: ComposerReasoningSpeedMenuViewController, context: Context) {}
}

private struct ComposerReasoningModelMenuSnapshot: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> ComposerReasoningModelMenuViewController {
        makeGroupedReasoningModelMenu()
    }

    func updateNSViewController(_ controller: ComposerReasoningModelMenuViewController, context: Context) {}
}

@MainActor
private func makeSnapshotPermissionOptions() -> [ChatComposerActionRowView.PermissionOptionPresentation] {
    ChatComposerPermissionPresentation.options(
        providerID: "codex",
        permissionModes: [
            PermissionModeOption(
                value: "untrusted",
                label: "Ask for approval",
                description: "Always ask to edit external files and use the internet."
            ),
            PermissionModeOption(
                value: "on-request",
                label: "Approve for me",
                description: "Only ask for actions detected as potentially unsafe."
            ),
            PermissionModeOption(
                value: "never",
                label: "Full access",
                description: "Unrestricted access to the internet and any file on your computer."
            )
        ]
    )
}

private struct ComposerPermissionMenuSnapshot: NSViewControllerRepresentable {
    let options: [ChatComposerActionRowView.PermissionOptionPresentation]

    func makeNSViewController(context: Context) -> ComposerPermissionMenuViewController {
        ComposerPermissionMenuViewController(
            options: options,
            selectedValue: "never",
            onPermissionSelected: { _ in },
            onRequestCloseMainMenu: {}
        )
    }

    func updateNSViewController(_ controller: ComposerPermissionMenuViewController, context: Context) {}
}

private struct ComposerWorktreeLocationMenuSnapshot: NSViewControllerRepresentable {
    let options: [ChatComposerActionRowView.WorktreeLocationOptionPresentation]

    func makeNSViewController(context: Context) -> ComposerWorktreeMenuViewController {
        ComposerWorktreeMenuViewController(
            options: options,
            selectedValue: ChatComposerWorktreeLocationPresentation.worktreeValue,
            onUseWorktreeSelected: { _ in },
            onRequestCloseMainMenu: {}
        )
    }

    func updateNSViewController(_ controller: ComposerWorktreeMenuViewController, context: Context) {}
}

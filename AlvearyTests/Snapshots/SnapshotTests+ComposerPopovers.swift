@preconcurrency import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testComposerReasoningMenuCollapsedContent() {
        let controller = makeSnapshotReasoningMenuController(
            configuration: makeSnapshotReasoningMenuConfiguration(groups: makeSingleProviderReasoningModelGroups())
        )

        assertMacSnapshot(
            ComposerReasoningMenuSnapshot(controller: controller),
            size: controller.preferredContentSize,
            named: "composer_reasoning_menu_collapsed_content",
            colorScheme: .dark
        )
    }

    func testComposerReasoningMenuExpandedSingleProviderContent() {
        let controller = makeSnapshotReasoningMenuController(
            configuration: makeSnapshotReasoningMenuConfiguration(groups: makeSingleProviderReasoningModelGroups())
        )
        controller.setModelsExpanded(true, animated: false)

        assertMacSnapshot(
            ComposerReasoningMenuSnapshot(controller: controller),
            size: controller.preferredContentSize,
            named: "composer_reasoning_menu_expanded_single_provider_content",
            colorScheme: .dark
        )
    }

    func testComposerReasoningMenuExpandedMultipleProvidersContent() {
        let controller = makeSnapshotReasoningMenuController(
            configuration: makeSnapshotReasoningMenuConfiguration(groups: makeMultipleProviderReasoningModelGroups())
        )
        controller.setModelsExpanded(true, animated: false)

        assertMacSnapshot(
            ComposerReasoningMenuSnapshot(controller: controller),
            size: controller.preferredContentSize,
            named: "composer_reasoning_menu_expanded_multiple_providers_content",
            colorScheme: .dark
        )
    }

    func testComposerReasoningMenuFastEnabledContent() {
        let controller = makeSnapshotReasoningMenuController(
            configuration: makeSnapshotReasoningMenuConfiguration(
                groups: makeSingleProviderReasoningModelGroups(),
                selectedSpeedMode: .fast
            )
        )

        assertMacSnapshot(
            ComposerReasoningMenuSnapshot(controller: controller),
            size: controller.preferredContentSize,
            named: "composer_reasoning_menu_fast_enabled_content",
            colorScheme: .dark
        )
    }

    func testComposerReasoningMenuEffortDraggingContent() throws {
        let controller = makeSnapshotReasoningMenuController(
            configuration: makeSnapshotReasoningMenuConfiguration(groups: makeSingleProviderReasoningModelGroups())
        )
        let size = controller.preferredContentSize
        let hostController = NSViewController()
        hostController.view = NSView(frame: NSRect(origin: .zero, size: size))
        hostController.addChild(controller)
        controller.loadViewIfNeeded()
        controller.view.frame = hostController.view.bounds
        hostController.view.addSubview(controller.view)
        controller.view.layoutSubtreeIfNeeded()
        let slider = try XCTUnwrap(controller.debugEffortSlider)
        let sliderFrame = slider.frame
        slider.beginTrackingInteraction(at: .zero)
        slider.updateTrackingInteraction(
            to: slider.displayedIndex,
            trackingPoint: NSPoint(x: ComposerReasoningEffortSliderMetrics.dragDirectionRevealDistance, y: 0)
        )
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(slider.frame, sliderFrame)

        assertMacSnapshot(
            ComposerReasoningMenuSnapshot(controller: hostController),
            size: size,
            named: "composer_reasoning_menu_effort_dragging_content",
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

    func testComposerTaskWorkspaceMenuContent() {
        let homeDirectory = NSHomeDirectory()
        let configuration = ChatComposerActionRowView.TaskWorkspaceConfiguration(
            primaryRoot: homeDirectory + "/Library/Application Support/com.afollestad.alveary/TaskWorkspaces/Private/task-123",
            grantedRoots: [
                homeDirectory + "/Development/alveary",
                homeDirectory + "/Documents/Reference"
            ],
            ownershipStrategy: .privateOwned,
            canEdit: true,
            disabledTooltip: nil,
            onAddFolders: { _ in },
            onRemoveGrant: { _ in }
        )
        let size = ComposerTaskWorkspaceMenuMetrics.contentSize(grantCount: configuration.grantedRoots.count)

        assertMacSnapshot(
            ComposerTaskWorkspaceMenuSnapshot(configuration: configuration),
            size: size,
            named: "composer_task_workspace_menu_content",
            colorScheme: .dark
        )
    }
}

@MainActor
private func makeSnapshotReasoningMenuConfiguration(
    groups: [ChatComposerActionRowView.ReasoningModelGroup],
    selectedSpeedMode: AgentSpeedMode = .standard
) -> ChatComposerActionRowView.ReasoningConfiguration {
    let selectedGroup = groups.first
    let selectedModel = selectedGroup?.options.first
    return makeReasoningConfiguration(
        modelGroups: groups,
        effortOptions: [
            .init(value: "low", title: "Low"),
            .init(value: "medium", title: "Medium"),
            .init(value: "high", title: "High"),
            .init(value: "xhigh", title: "Extra High"),
            .init(value: "max", title: "Max"),
            .init(value: "ultra", title: "Ultra")
        ],
        selectedProvider: selectedGroup?.providerID ?? "codex",
        selectedModel: selectedModel?.value ?? "gpt-5.6-sol",
        selectedEffort: "medium",
        selectedSpeedMode: selectedSpeedMode,
        supportsSpeedMode: true
    )
}

private struct ComposerReasoningMenuSnapshot: NSViewControllerRepresentable {
    let controller: NSViewController

    func makeNSViewController(context: Context) -> NSViewController {
        controller
    }

    func updateNSViewController(_ controller: NSViewController, context: Context) {}
}

@MainActor
private func makeSnapshotReasoningMenuController(
    configuration: ChatComposerActionRowView.ReasoningConfiguration
) -> ComposerReasoningMenuViewController {
    ComposerReasoningMenuViewController(configuration: configuration, onRequestCloseMainMenu: {})
}

@MainActor
private func makeSingleProviderReasoningModelGroups() -> [ChatComposerActionRowView.ReasoningModelGroup] {
    [
        .init(
            providerID: "codex",
            providerTitle: "Codex",
            options: [
                .init(providerID: "codex", value: "gpt-5.6-sol", title: "GPT-5.6-Sol"),
                .init(providerID: "codex", value: "gpt-5.6-luna", title: "GPT-5.6-Luna"),
                .init(providerID: "codex", value: "gpt-5.6-terra", title: "GPT-5.6-Terra"),
                .init(providerID: "codex", value: "gpt-5.5", title: "GPT-5.5")
            ]
        )
    ]
}

@MainActor
private func makeMultipleProviderReasoningModelGroups() -> [ChatComposerActionRowView.ReasoningModelGroup] {
    [
        .init(
            providerID: "claude",
            providerTitle: "Claude",
            options: [
                .init(providerID: "claude", value: "sonnet", title: "Sonnet"),
                .init(providerID: "claude", value: "fable", title: "Fable"),
                .init(providerID: "claude", value: "opus", title: "Opus"),
                .init(providerID: "claude", value: "haiku", title: "Haiku")
            ]
        ),
        .init(
            providerID: "codex",
            providerTitle: "Codex",
            options: [
                .init(providerID: "codex", value: "gpt-5.6-sol", title: "GPT-5.6-Sol"),
                .init(providerID: "codex", value: "gpt-5.6-luna", title: "GPT-5.6-Luna"),
                .init(providerID: "codex", value: "gpt-5.6-terra", title: "GPT-5.6-Terra"),
                .init(providerID: "codex", value: "gpt-5.5", title: "GPT-5.5")
            ]
        )
    ]
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

private struct ComposerTaskWorkspaceMenuSnapshot: NSViewControllerRepresentable {
    let configuration: ChatComposerActionRowView.TaskWorkspaceConfiguration

    func makeNSViewController(context: Context) -> ComposerTaskWorkspaceMenuViewController {
        ComposerTaskWorkspaceMenuViewController(
            configuration: configuration,
            onAddFolders: {},
            onRemoveGrant: { _ in },
            onRequestClose: {}
        )
    }

    func updateNSViewController(_ controller: ComposerTaskWorkspaceMenuViewController, context: Context) {}
}

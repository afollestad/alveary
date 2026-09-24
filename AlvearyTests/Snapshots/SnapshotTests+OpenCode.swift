import AgentCLIKit
@preconcurrency import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testOpenCodeModelPickerOpensExpanded() {
        let defaults = AgentDefaultModelOptions.staticOptions(for: .opencode).map {
            ChatComposerActionRowView.MenuOption(value: $0.id, title: $0.label)
        }
        let configuration = makeReasoningConfiguration(
            harnessOptions: [.init(value: "opencode", title: "OpenCode")],
            modelOptions: defaults + [.init(value: "opencode/big-pickle", title: "Big Pickle · OpenCode Zen")],
            effortOptions: [], selectedHarness: "opencode", selectedModel: "default"
        )
        let controller = ComposerReasoningMenuViewController(configuration: configuration, onRequestCloseMainMenu: {})
        controller.loadViewIfNeeded()
        assertMacSnapshot(
            OpenCodeMenuSnapshot(controller: controller),
            size: controller.preferredContentSize, named: "opencode_model_picker_expanded", colorScheme: .dark
        )
    }

    func testOpenCodePermissionMenu() {
        let options = ChatComposerPermissionPresentation.options(
            harnessID: "opencode",
            permissionModes: (OpenCodeHarnessDefinition.definition.supportedPermissionModes ?? []).map {
                PermissionModeOption(value: $0.value, label: $0.label, description: $0.description)
            }
        )
        let controller = ComposerPermissionMenuViewController(
            options: options, selectedValue: "ask", onPermissionSelected: { _ in }, onRequestCloseMainMenu: {}
        )
        assertMacSnapshot(
            OpenCodeMenuSnapshot(controller: controller),
            size: ComposerPermissionMenuMetrics.contentSize(options: options),
            named: "opencode_permissions", colorScheme: .dark
        )
    }

    func testOpenCodeComposerModelCapabilities() {
        let vision = AgentModelOption(
            harnessId: .opencode, id: "provider/vision", model: "provider/vision", label: "Vision",
            metadata: [OpenCodeModelMetadata.supportsImageInput: .bool(true)]
        )
        let status = AgentHarnessStatus(
            harnessId: .opencode, definition: OpenCodeHarnessDefinition.definition, modelOptions: [vision]
        )
        let unknown = HarnessFeaturePolicy(harnessID: "opencode", status: status)
        let known = HarnessFeaturePolicy(harnessID: "opencode", status: status, selectedModel: vision.id)
        let content = HStack(alignment: .top, spacing: 16) {
            openCodeComposerMenu(policy: unknown, title: "Default model")
            openCodeComposerMenu(policy: known, title: "Image-capable model")
        }
        .padding(12)
        assertMacSnapshot(content, size: CGSize(width: 528, height: 172), named: "opencode_model_capabilities", colorScheme: .dark)
    }

    func testOpenCodeInheritedUtilitySelection() {
        var settings = AppSettings()
        settings.defaultHarness = "opencode"
        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService(current: settings))
        assertMacSnapshot(
            SettingsFormSection { UtilityAgentSettingsRows(viewModel: viewModel) }.padding(16),
            size: CGSize(width: 610, height: 240), named: "opencode_utility_model_required"
        )
    }

    func testOpenCodeReviewTeamWithOptionalVariants() async {
        var settings = AppSettings()
        settings.pullRequestReviewMode = .reviewTeam
        settings.pullRequestReviewHarness = "opencode"
        settings.pullRequestReviewModel = "provider/text"
        settings.pullRequestReviewEffort = AppSettings.openCodeDefaultEffort
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer", harnessID: "opencode", model: "provider/reasoning", effort: "native")
        ]
        let status = SettingsViewModelTests.harnessStatus(for: .opencode, modelOptions: [
            AgentModelOption(harnessId: .opencode, id: "provider/text", model: "provider/text", label: "Text"),
            AgentModelOption(
                harnessId: .opencode, id: "provider/reasoning", model: "provider/reasoning", label: "Reasoning",
                supportedEffortOptions: [.init(value: "native", label: "Native", description: "")]
            )
        ])
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(current: settings),
            harnessDiscovery: SnapshotHarnessDiscoveryService(statuses: [.opencode: status])
        )
        await viewModel.refreshHarnessStatuses()
        assertMacSnapshot(
            PullRequestReviewTeamEditorSheet(viewModel: viewModel, draft: settings, onCancel: {}, onSave: { _ in }),
            size: CGSize(width: 760, height: 760), named: "opencode_review_team"
        )
    }

    func testOpenCodeFailedHarnessRecovery() async {
        let discovery = SnapshotHarnessDiscoveryService(statuses: [
            .opencode: AgentHarnessStatus(
                harnessId: .opencode,
                definition: OpenCodeHarnessDefinition.definition,
                installation: .installed,
                availability: AgentHarnessAvailability(
                    harnessId: .opencode,
                    executablePath: "/Users/test/.opencode/bin/opencode",
                    versionDescription: "1.18.21"
                ),
                setup: .failed,
                diagnostics: ["OpenCode server version 1.18.21 requires >=1.18.31 and <2.0.0."]
            )
        ])
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(),
            harnessDiscovery: discovery
        )
        await viewModel.refreshHarnessStatuses()

        let content = VStack(alignment: .leading, spacing: 20) {
            SettingsScreenHeader(
                title: "Harnesses",
                description: "Manage installed coding agents.",
                refresh: .init(accessibilityLabel: "Refresh harness statuses", isRefreshing: false, action: {}),
                onClose: nil
            )
            SettingsAgentCard(viewModel: viewModel, harnessID: "opencode")
        }
        .padding(24)
        assertMacSnapshot(content, size: CGSize(width: 620, height: 360), named: "opencode_failed_harness_recovery")
    }

    private func openCodeComposerMenu(policy: HarnessFeaturePolicy, title: String) -> some View {
        let controller = ComposerPlusMenuViewController(configuration: .init(
            showsGoalMode: policy.supportsGoalMode,
            isGoalModeArmed: false,
            isGoalModeToggleEnabled: false,
            goalModeDisabledTooltip: nil,
            isPlanModeEnabled: false,
            isPlanModeToggleEnabled: policy.supportsPlanMode,
            planModeDisabledTooltip: nil,
            onAddPhotosAndFiles: {},
            allowsPhotoAttachments: policy.supportsLocalImageInput,
            appShotAppName: policy.supportsAppShots ? "Xcode" : nil,
            appShotAppIcon: nil,
            onPlanModeChange: { _ in },
            onGoalModeChange: { _ in }
        ))
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            OpenCodeMenuSnapshot(controller: controller)
                .frame(width: controller.preferredContentSize.width, height: controller.preferredContentSize.height)
        }
    }
}

private struct OpenCodeMenuSnapshot: NSViewControllerRepresentable {
    let controller: NSViewController
    func makeNSViewController(context: Context) -> NSViewController { controller }
    func updateNSViewController(_ controller: NSViewController, context: Context) {}
}

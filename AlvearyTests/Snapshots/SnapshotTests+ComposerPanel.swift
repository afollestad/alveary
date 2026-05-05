import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testChatComposerPanelErrorBannerWithRetryAction() throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.lastTurnError = "Session handoff failed: the hidden handoff prompt returned no context."
        fixture.viewModel.state.failedSessionHandoffMessage = fixture.viewModel.lastTurnError

        assertMacSnapshot(
            ChatComposerPanelSnapshotView(
                viewModel: fixture.viewModel,
                composerCapabilities: composerPanelSnapshotCapabilities
            ),
            size: CGSize(width: 1000, height: 210),
            named: "chat_composer_panel_error_banner_retry",
            colorScheme: .dark
        )
    }

    func testChatComposerPanelWithoutBanners() throws {
        let fixture = try ConversationViewModelTestFixture()

        assertMacSnapshot(
            ChatComposerPanelSnapshotView(
                viewModel: fixture.viewModel,
                composerCapabilities: composerPanelSnapshotCapabilities
            ),
            size: CGSize(width: 1000, height: 150),
            named: "chat_composer_panel_without_banners",
            colorScheme: .dark
        )
    }

    func testAppKitComposerPanelWithNativeActionRow() {
        assertMacSnapshot(
            AppKitComposerPanelNativeRowSnapshot(),
            size: CGSize(width: 1000, height: 150),
            named: "appkit_composer_panel_native_action_row",
            colorScheme: .dark
        )
    }

    func testAppKitComposerPanelWithNativeTopContent() {
        assertMacSnapshot(
            AppKitComposerPanelNativeRowSnapshot(
                topContentConfiguration: .init(items: [
                    .stagedContext(.init(
                        context: "Restoring context from local history.",
                        onDismiss: {}
                    ))
                ]),
                inputOuterPadding: ChatComposerPanelLayout.nativeInputPaddingWithTop
            ),
            size: CGSize(width: 1000, height: 190),
            named: "appkit_composer_panel_native_top_content",
            colorScheme: .dark
        )
    }

    private var composerPanelSnapshotCapabilities: ComposerCapabilities {
        ComposerCapabilities(
            supportedEffortLevels: ["low", "medium", "high"],
            supportedPermissionModes: samplePermissionModes,
            supportsMidTurnSteering: true
        )
    }
}

private struct AppKitComposerPanelNativeRowSnapshot: View {
    let topContentConfiguration: AppKitChatComposerTopContentView.Configuration
    let inputOuterPadding: EdgeInsets
    let usageSummary = ConversationUsageSummary(
        contextUsedTokens: 186_000,
        contextWindowSize: 200_000,
        totalCostUsd: 1.42,
        hasReportedUsage: true,
        isUsingCachedContextWindow: false
    )

    @State private var text = ""
    @State private var selectedModel = "sonnet"
    @State private var selectedEffort = "medium"
    @State private var selectedPermissionMode = "default"
    @State private var selectedUseWorktree = false
    @State private var focusRequestToken: UUID?
    @State private var isStopConfirmationArmed = false

    init(
        topContentConfiguration: AppKitChatComposerTopContentView.Configuration = .empty,
        inputOuterPadding: EdgeInsets = ChatComposerPanelLayout.nativeInputPadding
    ) {
        self.topContentConfiguration = topContentConfiguration
        self.inputOuterPadding = inputOuterPadding
    }

    var body: some View {
        AppKitComposerPanelSnapshotRepresentable(
            content: AnyView(content),
            topContentConfiguration: topContentConfiguration,
            actionRowConfiguration: actionRowConfiguration
        )
    }

    private var content: some View {
        ChatInputField(
            text: $text,
            mode: .idle,
            defaultEnterBehavior: .queue,
            onSubmit: {},
            onSteer: {},
            onStop: {},
            isStopConfirmationArmed: $isStopConfirmationArmed,
            outerPadding: inputOuterPadding,
            selectedModel: $selectedModel,
            selectedEffort: $selectedEffort,
            selectedPermissionMode: $selectedPermissionMode,
            selectedUseWorktree: $selectedUseWorktree,
            supportedPermissionModes: Self.permissionModes,
            supportedEffortLevels: ["low", "medium", "high"],
            showWorktreePicker: false,
            sessionLocationLabel: "Local",
            usageSummary: usageSummary,
            supportsMidTurnSteering: true,
            workingDirectory: "/tmp/alveary",
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] },
            focusRequestToken: $focusRequestToken,
            showsActionRow: false
        )
    }

    private var actionRowConfiguration: ChatComposerActionRowView.Configuration {
        ChatComposerActionRowView.Configuration(
            modelOptions: AppSettings.supportedModels.map {
                .init(value: $0, title: ChatInputFieldTextSupport.modelLabel(for: $0))
            },
            selectedModel: selectedModel,
            supportedEffortLevels: ["low", "medium", "high"].map {
                .init(value: $0, title: ChatInputFieldTextSupport.effortLabel(for: $0))
            },
            selectedEffort: selectedEffort,
            supportedPermissionModes: Self.permissionModes.map {
                .init(value: $0.value, title: ChatInputFieldTextSupport.permissionModeLabel(for: $0))
            },
            selectedPermissionMode: selectedPermissionMode,
            showWorktreePicker: false,
            selectedUseWorktree: selectedUseWorktree,
            sessionLocationLabel: "Local",
            usageSummary: usageSummary,
            isTextEditorDisabled: false,
            areControlsDisabled: false,
            mode: .idle,
            primaryActionTitle: "Send",
            primaryActionSystemImage: "paperplane.fill",
            isPrimaryActionDisabled: true,
            isStopConfirmationArmed: isStopConfirmationArmed,
            composerActionRowHeight: ChatComposerActionRowView.defaultHeight,
            contextIndicatorKeyboardSpacing: ChatComposerActionRowView.defaultContextIndicatorKeyboardSpacing,
            onModelChange: { selectedModel = $0 },
            onEffortChange: { selectedEffort = $0 },
            onPermissionModeChange: { selectedPermissionMode = $0 },
            onUseWorktreeChange: { selectedUseWorktree = $0 },
            onSubmit: {},
            onStop: {},
            onShowKeymap: {}
        )
    }

    private static var permissionModes: [PermissionModeOption] {
        [
            PermissionModeOption(value: "default", label: "Default permissions", description: "Prompt before restricted tool actions."),
            PermissionModeOption(value: "acceptEdits", label: "Accept edits", description: "Allow edit tools without asking."),
            PermissionModeOption(value: "auto", label: "Automatic", description: "Allow safe actions automatically.")
        ]
    }
}

private struct AppKitComposerPanelSnapshotRepresentable: NSViewRepresentable {
    let content: AnyView
    let topContentConfiguration: AppKitChatComposerTopContentView.Configuration
    let actionRowConfiguration: ChatComposerActionRowView.Configuration

    func makeNSView(context: Context) -> AppKitChatComposerPanelView {
        let view = AppKitChatComposerPanelView()
        view.configure(configuration)
        return view
    }

    func updateNSView(_ view: AppKitChatComposerPanelView, context: Context) {
        view.configure(configuration)
    }

    private var configuration: AppKitChatComposerPanelConfiguration {
        AppKitChatComposerPanelConfiguration(
            content: content,
            topContentConfiguration: topContentConfiguration,
            actionRowConfiguration: actionRowConfiguration,
            showsTopDivider: true,
            hasTopContent: false,
            layout: AppKitChatComposerPanelView.Layout(
                horizontalPadding: ChatComposerPanelLayout.appKitHorizontalPadding,
                topContentSpacing: ChatComposerPanelLayout.topContentSpacing,
                actionRowSpacing: ChatComposerPanelLayout.actionRowSpacing,
                bottomPadding: ChatComposerPanelLayout.nativeActionRowBottomPadding
            )
        )
    }
}

private struct ChatComposerPanelSnapshotView: View {
    let viewModel: ConversationViewModel
    let composerCapabilities: ComposerCapabilities

    @State private var selectedModel = "sonnet"
    @State private var selectedEffort = "medium"
    @State private var selectedPermissionMode = "default"
    @State private var selectedUseWorktree = false
    @State private var focusRequestToken: UUID?

    var body: some View {
        ChatComposerPanel(
            viewModel: viewModel,
            composerCapabilities: composerCapabilities,
            workingDirectory: "/tmp/alveary",
            showsTopDivider: true,
            composerMode: .idle,
            defaultEnterBehavior: .queue,
            composerIsBusy: false,
            isProjectTrustBlocked: false,
            selectedModel: $selectedModel,
            selectedEffort: $selectedEffort,
            selectedPermissionMode: $selectedPermissionMode,
            selectedUseWorktree: $selectedUseWorktree,
            showWorktreePicker: false,
            sessionLocationLabel: nil,
            usageSummary: nil,
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] },
            onSubmit: {},
            onSteer: {},
            onStop: {},
            focusRequestToken: $focusRequestToken
        )
    }
}

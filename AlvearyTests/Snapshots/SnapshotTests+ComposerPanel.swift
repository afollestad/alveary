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

    func testAppKitComposerPanelWithNativeActionRowLight() {
        assertMacSnapshot(
            AppKitComposerPanelNativeRowSnapshot(),
            size: CGSize(width: 1000, height: 150),
            named: "appkit_composer_panel_native_action_row_light",
            colorScheme: .light
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
                ])
            ),
            size: CGSize(width: 1000, height: 190),
            named: "appkit_composer_panel_native_top_content",
            colorScheme: .dark
        )
    }

    func testAppKitComposerPanelWithNativeQueuedMessages() {
        assertMacSnapshot(
            AppKitComposerPanelNativeRowSnapshot(
                queuedMessages: [
                    QueuedMessage(
                        text: "Follow with the snapshot cleanup once the diff finishes loading.",
                        stagedContext: "Restoring context from local history."
                    )
                ]
            ),
            size: CGSize(width: 1000, height: 220),
            named: "appkit_composer_panel_native_queued_messages",
            colorScheme: .dark
        )
    }

    func testAppKitComposerPanelWithNativeQueuedMessagesLight() {
        assertMacSnapshot(
            AppKitComposerPanelNativeRowSnapshot(
                queuedMessages: [
                    QueuedMessage(
                        text: "Follow with the snapshot cleanup once the diff finishes loading.",
                        stagedContext: "Restoring context from local history."
                    )
                ]
            ),
            size: CGSize(width: 1000, height: 220),
            named: "appkit_composer_panel_native_queued_messages_light",
            colorScheme: .light
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
    let queuedMessages: [QueuedMessage]
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
    @Environment(\.colorScheme) private var colorScheme

    init(
        topContentConfiguration: AppKitChatComposerTopContentView.Configuration = .empty,
        queuedMessages: [QueuedMessage] = []
    ) {
        self.topContentConfiguration = topContentConfiguration
        self.queuedMessages = queuedMessages
    }

    var body: some View {
        AppKitComposerPanelSnapshotRepresentable(
            bodyConfiguration: bodyConfiguration,
            topContentConfiguration: topContentConfiguration,
            queuedMessagesConfiguration: queuedMessagesConfiguration,
            actionRowConfiguration: actionRowConfiguration
        )
    }

    private var bodyConfiguration: AppKitChatComposerBodyConfiguration {
        AppKitChatComposerBodyConfiguration(
            text: text,
            mode: .idle,
            defaultEnterBehavior: .queue,
            isStopConfirmationArmed: isStopConfirmationArmed,
            supportsMidTurnSteering: true,
            isProjectTrustBlocked: false,
            isHandoffSteeringPromptActive: false,
            isHandoffOutputPromptActive: false,
            handoffSteeringCountdown: nil,
            sendCountdown: nil,
            hasQueuedMessages: !queuedMessages.isEmpty,
            hasTopContent: !topContentConfiguration.items.isEmpty,
            workingDirectory: "/tmp/alveary",
            requestFirstResponder: focusRequestToken,
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] },
            onSubmit: {},
            onSteer: {},
            onStop: {},
            onStopConfirmationChange: { isStopConfirmationArmed = $0 },
            onFocusRequestConsumed: { consumedToken in
                guard focusRequestToken == consumedToken else {
                    return
                }
                focusRequestToken = nil
            }
        )
    }

    private var queuedMessagesConfiguration: AppKitChatQueuedMessagesConfiguration? {
        guard !queuedMessages.isEmpty else {
            return nil
        }
        return AppKitChatQueuedMessagesConfiguration(
            queuedMessages: queuedMessages,
            supportsMidTurnSteering: true,
            isTurnActive: true,
            inFlightQueuedMessageID: nil,
            borderWidth: 1,
            onSteer: { _ in },
            onEdit: { _ in },
            onDismiss: { _ in }
        )
    }

    private var actionRowConfiguration: ChatComposerActionRowView.Configuration {
        ChatComposerActionRowView.Configuration(
            modelOptions: AppSettings.supportedModels.map {
                .init(value: $0, title: ChatComposerTextSupport.modelLabel(for: $0))
            },
            selectedModel: selectedModel,
            supportedEffortLevels: ["low", "medium", "high"].map {
                .init(value: $0, title: ChatComposerTextSupport.effortLabel(for: $0))
            },
            selectedEffort: selectedEffort,
            supportedPermissionModes: Self.permissionModes.map {
                .init(value: $0.value, title: ChatComposerTextSupport.permissionModeLabel(for: $0))
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
    let bodyConfiguration: AppKitChatComposerBodyConfiguration
    let topContentConfiguration: AppKitChatComposerTopContentView.Configuration
    let queuedMessagesConfiguration: AppKitChatQueuedMessagesConfiguration?
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
            bodyConfiguration: bodyConfiguration,
            topContentConfiguration: topContentConfiguration,
            queuedMessagesConfiguration: queuedMessagesConfiguration,
            actionRowConfiguration: actionRowConfiguration,
            showsTopDivider: true,
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

    var body: some View {
        AppKitComposerPanelNativeRowSnapshot(
            topContentConfiguration: .init(items: topContentItems)
        )
    }

    private var topContentItems: [AppKitChatComposerTopContentView.Item] {
        if let lastTurnError = viewModel.lastTurnError {
            return [
                .inlineBanner(.init(
                    message: lastTurnError,
                    severity: .error,
                    actionTitle: viewModel.canRetryFailedSessionHandoff ? "Retry" : nil,
                    onAction: viewModel.canRetryFailedSessionHandoff ? {} : nil,
                    onDismiss: viewModel.canRetryFailedSessionHandoff ? nil : {}
                ))
            ]
        }
        return []
    }
}

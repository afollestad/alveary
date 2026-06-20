@preconcurrency import AppKit
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

    func testComposerPlusMenuCompactContent() {
        assertMacSnapshot(
            ComposerPlusMenuSnapshot(),
            size: CGSize(width: 244, height: 84),
            named: "composer_plus_menu_compact_content",
            colorScheme: .dark
        )
    }

    func testAppKitComposerPanelWithAskUserQuestionOverlay() {
        assertMacSnapshot(
            AppKitComposerPanelNativeRowSnapshot(
                interactionOverlayConfiguration: askUserQuestionOverlayConfiguration
            ),
            size: CGSize(width: 1000, height: 217),
            named: "appkit_composer_panel_ask_user_question_overlay",
            colorScheme: .dark
        )
    }

    func testAppKitComposerPanelWithExitPlanModeOverlay() {
        assertMacSnapshot(
            AppKitComposerPanelNativeRowSnapshot(
                interactionOverlayConfiguration: exitPlanModeOverlayConfiguration
            ),
            size: CGSize(width: 1000, height: 160),
            named: "appkit_composer_panel_exit_plan_mode_overlay",
            colorScheme: .dark
        )
    }

    private var composerPanelSnapshotCapabilities: ComposerCapabilities {
        ComposerCapabilities(
            supportedPermissionModes: samplePermissionModes,
            supportsMidTurnSteering: true
        )
    }

    private var askUserQuestionOverlayConfiguration: AppKitComposerOverlayConfiguration {
        AppKitComposerOverlayConfiguration(
            id: "ask-user-question-snapshot",
            panelConfiguration: AppKitComposerOverlayPanelView.Configuration(
                title: "Which implementation path should we take?",
                rows: [
                    AppKitComposerOverlayOptionRowView.Configuration(
                        id: "direct",
                        indexText: "1.",
                        title: "Direct implementation",
                        helpText: "Make the smallest focused change.",
                        isSelected: true,
                        showsSelectedChip: true,
                        isFocused: true,
                        fontSize: AppKitComposerOverlayMetrics.compactOptionFontSize,
                        fontWeight: AppKitComposerOverlayMetrics.compactOptionFontWeight,
                        minimumHeight: AppKitComposerOverlayMetrics.compactOptionMinimumHeight,
                        verticalPadding: AppKitComposerOverlayMetrics.compactOptionVerticalPadding,
                        customFieldHeight: AppKitComposerOverlayMetrics.compactCustomFieldHeight,
                        onSelect: {}
                    ),
                    AppKitComposerOverlayOptionRowView.Configuration(
                        id: "refactor",
                        indexText: "2.",
                        title: "Refactor shared behavior",
                        helpText: "Extract a reusable path before implementing.",
                        fontSize: AppKitComposerOverlayMetrics.compactOptionFontSize,
                        fontWeight: AppKitComposerOverlayMetrics.compactOptionFontWeight,
                        minimumHeight: AppKitComposerOverlayMetrics.compactOptionMinimumHeight,
                        verticalPadding: AppKitComposerOverlayMetrics.compactOptionVerticalPadding,
                        customFieldHeight: AppKitComposerOverlayMetrics.compactCustomFieldHeight,
                        onSelect: {}
                    ),
                    AppKitComposerOverlayOptionRowView.Configuration(
                        id: "custom",
                        indexText: "3.",
                        title: "",
                        customPlaceholder: "No, and tell the agent what to do differently",
                        fontSize: AppKitComposerOverlayMetrics.compactOptionFontSize,
                        fontWeight: AppKitComposerOverlayMetrics.compactOptionFontWeight,
                        minimumHeight: AppKitComposerOverlayMetrics.compactOptionMinimumHeight,
                        verticalPadding: AppKitComposerOverlayMetrics.compactOptionVerticalPadding,
                        customFieldHeight: AppKitComposerOverlayMetrics.compactCustomFieldHeight,
                        onSelect: {}
                    )
                ],
                pageText: "1 of 2",
                canNavigateForward: true,
                primaryTitle: "Continue",
                onDismiss: {},
                onPrimary: {}
            )
        )
    }

    private var exitPlanModeOverlayConfiguration: AppKitComposerOverlayConfiguration {
        AppKitComposerOverlayConfiguration(
            id: "exit-plan-mode-snapshot",
            panelConfiguration: AppKitComposerOverlayPanelView.Configuration(
                title: "Implement this plan?",
                rows: [
                    AppKitComposerOverlayOptionRowView.Configuration(
                        id: "yes",
                        indexText: "1.",
                        title: "Yes, implement this plan",
                        isSelected: true,
                        isFocused: true,
                        fontSize: AppKitComposerOverlayMetrics.compactOptionFontSize,
                        fontWeight: AppKitComposerOverlayMetrics.compactOptionFontWeight,
                        minimumHeight: AppKitComposerOverlayMetrics.compactOptionMinimumHeight,
                        verticalPadding: AppKitComposerOverlayMetrics.compactOptionVerticalPadding,
                        customFieldHeight: AppKitComposerOverlayMetrics.compactCustomFieldHeight,
                        onSelect: {}
                    ),
                    AppKitComposerOverlayOptionRowView.Configuration(
                        id: "no",
                        indexText: "2.",
                        title: "",
                        customPlaceholder: "No, and tell the agent what to do differently",
                        fontSize: AppKitComposerOverlayMetrics.compactOptionFontSize,
                        fontWeight: AppKitComposerOverlayMetrics.compactOptionFontWeight,
                        minimumHeight: AppKitComposerOverlayMetrics.compactOptionMinimumHeight,
                        verticalPadding: AppKitComposerOverlayMetrics.compactOptionVerticalPadding,
                        customFieldHeight: AppKitComposerOverlayMetrics.compactCustomFieldHeight,
                        usesInlineCustomPlaceholder: true,
                        onSelect: {}
                    )
                ],
                density: exitPlanModeOverlayDensity,
                titleFont: .systemFont(ofSize: 14, weight: .semibold),
                primaryTitle: "Submit",
                onDismiss: {},
                onPrimary: {}
            )
        )
    }

    private var exitPlanModeOverlayDensity: AppKitComposerOverlayPanelDensity {
        AppKitComposerOverlayPanelDensity(
            panelPadding: AppKitComposerOverlayMetrics.regularDensity.panelPadding,
            topPadding: AppKitComposerOverlayMetrics.regularDensity.topPadding,
            headerRowsSpacing: AppKitComposerOverlayMetrics.regularDensity.headerRowsSpacing,
            rowSpacing: 0,
            footerSpacing: 4,
            placesFooterInlineWithLastRow: false,
            bottomClearance: 12
        )
    }
}

// Shared with `SnapshotTests+ComposerQueuedMessages.swift`.
struct AppKitComposerPanelNativeRowSnapshot: View {
    let topContentConfiguration: AppKitChatComposerTopContentView.Configuration
    let queuedMessages: [QueuedMessage]
    let interactionOverlayConfiguration: AppKitComposerOverlayConfiguration?
    let usageSummary = ConversationUsageSummary(
        contextUsedTokens: 186_000,
        contextWindowSize: 200_000,
        totalCostUsd: 1.42,
        hasReportedCost: true,
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
        queuedMessages: [QueuedMessage] = [],
        interactionOverlayConfiguration: AppKitComposerOverlayConfiguration? = nil
    ) {
        self.topContentConfiguration = topContentConfiguration
        self.queuedMessages = queuedMessages
        self.interactionOverlayConfiguration = interactionOverlayConfiguration
    }

    var body: some View {
        AppKitComposerPanelSnapshotRepresentable(
            bodyConfiguration: bodyConfiguration,
            topContentConfiguration: topContentConfiguration,
            queuedMessagesConfiguration: queuedMessagesConfiguration,
            actionRowConfiguration: actionRowConfiguration,
            interactionOverlayConfiguration: interactionOverlayConfiguration
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
        let modelOptions = AgentModelOptionTestFixtures.claudeModelOptions.map {
            ChatComposerActionRowView.MenuOption(value: $0.id, title: $0.label)
        }
        let effortOptions = ["low", "medium", "high"].map {
            ChatComposerActionRowView.MenuOption(value: $0, title: ChatComposerTextSupport.effortLabel(for: $0))
        }
        return ChatComposerActionRowView.Configuration(
            reasoning: makeReasoningConfiguration(
                providerOptions: [.init(value: "claude", title: "Claude Code")],
                modelOptions: modelOptions,
                effortOptions: effortOptions,
                selectedModel: selectedModel,
                selectedEffort: selectedEffort,
                hasStartedThread: true,
                onEffortChange: {
                    selectedEffort = $0
                    return true
                },
                onModelChange: { request in
                    selectedModel = request.modelID
                    return .applied(
                        selection: makeReasoningConfiguration(
                            modelOptions: modelOptions,
                            effortOptions: effortOptions,
                            selectedModel: request.modelID,
                            selectedEffort: selectedEffort,
                            hasStartedThread: true
                        ).selection
                    )
                }
            ),
            supportedPermissionModes: ChatComposerPermissionPresentation.options(
                providerID: "claude",
                permissionModes: Self.permissionModes
            ),
            selectedPermissionMode: selectedPermissionMode,
            showWorktreePicker: false,
            selectedUseWorktree: selectedUseWorktree,
            usageSummary: usageSummary,
            areControlsDisabled: false,
            mode: .idle,
            primaryActionTitle: "Send",
            primaryActionSystemImage: "paperplane.fill",
            isPrimaryActionDisabled: true,
            isStopConfirmationArmed: isStopConfirmationArmed,
            composerActionRowHeight: ChatComposerActionRowView.defaultHeight,
            onPermissionModeChange: { selectedPermissionMode = $0 },
            onUseWorktreeChange: { selectedUseWorktree = $0 },
            onSubmit: {},
            onStop: {}
        )
    }

    private static var permissionModes: [PermissionModeOption] {
        [
            PermissionModeOption(value: "default", label: "Default", description: "Ask before file edits and restricted tool actions."),
            PermissionModeOption(
                value: "acceptEdits",
                label: "Accept edits",
                description: "Automatically allow file edits, but ask for other sensitive actions."
            ),
            PermissionModeOption(value: "auto", label: "Automatic", description: "Automatically approve most actions with safety checks.")
        ]
    }
}

private struct ComposerPlusMenuSnapshot: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> ComposerPlusMenuViewController {
        ComposerPlusMenuViewController(configuration: .init(
            isPlanModeEnabled: true,
            isPlanModeToggleEnabled: true,
            planModeDisabledTooltip: nil,
            onAddPhotosAndFiles: {},
            onPlanModeChange: { _ in }
        ))
    }

    func updateNSViewController(_ controller: ComposerPlusMenuViewController, context: Context) {}
}

private struct AppKitComposerPanelSnapshotRepresentable: NSViewRepresentable {
    let bodyConfiguration: AppKitChatComposerBodyConfiguration
    let topContentConfiguration: AppKitChatComposerTopContentView.Configuration
    let queuedMessagesConfiguration: AppKitChatQueuedMessagesConfiguration?
    let actionRowConfiguration: ChatComposerActionRowView.Configuration
    let interactionOverlayConfiguration: AppKitComposerOverlayConfiguration?

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
            interactionOverlayConfiguration: interactionOverlayConfiguration,
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

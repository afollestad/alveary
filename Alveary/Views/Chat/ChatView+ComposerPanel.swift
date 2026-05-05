import AppKit
import SwiftUI

enum ChatComposerPanelLayout {
    static let appKitHorizontalPadding = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 21)
    static let swiftUIHorizontalPadding = EdgeInsets(
        top: appKitHorizontalPadding.top,
        leading: appKitHorizontalPadding.left,
        bottom: appKitHorizontalPadding.bottom,
        trailing: appKitHorizontalPadding.right
    )
    static let verticalPadding: CGFloat = 0
    static let topContentSpacing: CGFloat = 8
    static let actionRowSpacing: CGFloat = 14
    // These are the visible top/bottom clearances inside the SwiftUI composer shell.
    // When AppKit owns the action row, bottom clearance moves to the panel so it
    // sits below the row instead of stacking between the editor and controls.
    static let inputOuterPadding = EdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0)
    static let inputOuterPaddingWithTopContent = EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 0)
    static let nativeInputPadding = EdgeInsets(top: 16, leading: 0, bottom: 0, trailing: 0)
    static let nativeInputPaddingWithTop = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
}

struct ChatComposerPanel: View {
    let viewModel: ConversationViewModel
    let composerCapabilities: ComposerCapabilities
    let workingDirectory: String?
    let showsTopDivider: Bool
    let composerMode: ComposerMode
    let defaultEnterBehavior: ThreadEnterDefaultBehavior
    let composerIsBusy: Bool
    let isProjectTrustBlocked: Bool
    let selectedModel: Binding<String>
    let selectedEffort: Binding<String>
    let selectedPermissionMode: Binding<String>
    let selectedUseWorktree: Binding<Bool>
    let showWorktreePicker: Bool
    let sessionLocationLabel: String?
    let usageSummary: ConversationUsageSummary?
    let loadFileCompletions: @Sendable () async -> [String]
    let loadSkillCompletions: @Sendable () async -> [Skill]
    let onSubmit: () -> Void
    let onSteer: () -> Void
    let onStop: () -> Void
    @Binding var focusRequestToken: UUID?
    @State private var isStopConfirmationArmed = false

    private var hasTopContent: Bool {
        viewModel.lastTurnError != nil ||
            viewModel.sessionContinuityNotice != nil ||
            viewModel.stagedContext != nil
    }

    var body: some View {
        ChatComposerPanelContent(
            viewModel: viewModel,
            composerCapabilities: composerCapabilities,
            workingDirectory: workingDirectory,
            composerMode: composerMode,
            defaultEnterBehavior: defaultEnterBehavior,
            composerIsBusy: composerIsBusy,
            isProjectTrustBlocked: isProjectTrustBlocked,
            selectedModel: selectedModel,
            selectedEffort: selectedEffort,
            selectedPermissionMode: selectedPermissionMode,
            selectedUseWorktree: selectedUseWorktree,
            showWorktreePicker: showWorktreePicker,
            sessionLocationLabel: sessionLocationLabel,
            usageSummary: usageSummary,
            loadFileCompletions: loadFileCompletions,
            loadSkillCompletions: loadSkillCompletions,
            onSubmit: onSubmit,
            onSteer: onSteer,
            onStop: onStop,
            focusRequestToken: $focusRequestToken,
            isStopConfirmationArmed: $isStopConfirmationArmed,
            usesNativeActionRow: false
        )
        .padding(.top, hasTopContent ? ChatComposerPanelLayout.topContentSpacing : 0)
        .padding(ChatComposerPanelLayout.swiftUIHorizontalPadding)
        .padding(.vertical, ChatComposerPanelLayout.verticalPadding)
        .background {
            Rectangle()
                .fill(.bar)
        }
        .overlay(alignment: .top) {
            if showsTopDivider {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 1)
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showsTopDivider)
    }
}

struct ChatComposerPanelContent: View {
    let viewModel: ConversationViewModel
    let composerCapabilities: ComposerCapabilities
    let workingDirectory: String?
    let composerMode: ComposerMode
    let defaultEnterBehavior: ThreadEnterDefaultBehavior
    let composerIsBusy: Bool
    let isProjectTrustBlocked: Bool
    let selectedModel: Binding<String>
    let selectedEffort: Binding<String>
    let selectedPermissionMode: Binding<String>
    let selectedUseWorktree: Binding<Bool>
    let showWorktreePicker: Bool
    let sessionLocationLabel: String?
    let usageSummary: ConversationUsageSummary?
    let loadFileCompletions: @Sendable () async -> [String]
    let loadSkillCompletions: @Sendable () async -> [Skill]
    let onSubmit: () -> Void
    let onSteer: () -> Void
    let onStop: () -> Void
    @Binding var focusRequestToken: UUID?
    @Binding var isStopConfirmationArmed: Bool
    let usesNativeActionRow: Bool

    // Filter the provider's full effort list to those that the current model
    // supports (e.g. Opus 4.7's `xhigh`). Intersect with the provider list
    // instead of replacing it so a provider that ships a narrower set (future
    // adapters) stays authoritative.
    private var visibleEffortLevels: [String] {
        ComposerSettingsPresentation.visibleEffortLevels(
            selectedModel: selectedModel.wrappedValue,
            providerSupportedEffortLevels: composerCapabilities.supportedEffortLevels
        )
    }

    var hasTopContent: Bool {
        viewModel.lastTurnError != nil ||
            viewModel.sessionContinuityNotice != nil ||
            viewModel.stagedContext != nil
    }

    private var inputOuterPadding: EdgeInsets {
        if usesNativeActionRow {
            return hasTopContent ?
                ChatComposerPanelLayout.nativeInputPaddingWithTop :
                ChatComposerPanelLayout.nativeInputPadding
        }
        return hasTopContent ? ChatComposerPanelLayout.inputOuterPaddingWithTopContent : ChatComposerPanelLayout.inputOuterPadding
    }

    var body: some View {
        VStack(spacing: ChatComposerPanelLayout.topContentSpacing) {
            if let lastTurnError = viewModel.lastTurnError {
                if viewModel.canRetryFailedSessionHandoff {
                    InlineBanner(
                        message: lastTurnError,
                        severity: .error,
                        autoDismissAfter: nil,
                        actionTitle: "Retry",
                        onAction: {
                            viewModel.retryFailedSessionHandoff()
                        }
                    )
                } else {
                    InlineBanner(
                        message: lastTurnError,
                        severity: .error,
                        autoDismissAfter: nil,
                        onDismiss: { viewModel.lastTurnError = nil }
                    )
                }
            }

            if let sessionContinuityNotice = viewModel.sessionContinuityNotice {
                InlineBanner(
                    message: sessionContinuityNotice,
                    severity: .warning,
                    autoDismissAfter: nil,
                    onDismiss: { viewModel.sessionContinuityNotice = nil }
                )
            }

            if let stagedContext = viewModel.stagedContext {
                StagedContextBanner(context: stagedContext) {
                    viewModel.dismissStagedContext()
                }
            }

            ChatInputField(
                text: Bindable(viewModel.state).inputDraft,
                mode: composerMode,
                defaultEnterBehavior: defaultEnterBehavior,
                onSubmit: onSubmit,
                onSteer: onSteer,
                onStop: onStop,
                isStopConfirmationArmed: $isStopConfirmationArmed,
                outerPadding: inputOuterPadding,
                selectedModel: selectedModel,
                selectedEffort: selectedEffort,
                selectedPermissionMode: selectedPermissionMode,
                selectedUseWorktree: selectedUseWorktree,
                supportedPermissionModes: composerCapabilities.supportedPermissionModes,
                supportedEffortLevels: visibleEffortLevels,
                showWorktreePicker: showWorktreePicker,
                sessionLocationLabel: sessionLocationLabel,
                usageSummary: usageSummary,
                supportsMidTurnSteering: composerCapabilities.supportsMidTurnSteering,
                queuedMessages: viewModel.messageQueue.pending,
                isTurnActive: viewModel.state.turnState.isActive,
                isProjectTrustBlocked: isProjectTrustBlocked,
                inFlightQueuedMessageID: viewModel.state.inFlightQueuedMessageID,
                isHandoffSteeringPromptActive: viewModel.state.isAwaitingHandoffSteering,
                isHandoffOutputPromptActive: viewModel.state.pendingHandoffOutput != nil,
                handoffSteeringCountdown: viewModel.state.handoffSteeringCountdownRemaining,
                sendCountdown: viewModel.state.handoffCountdownRemaining,
                onSteerQueuedMessage: { messageID in
                    Task { try? await viewModel.steerQueuedMessage(id: messageID) }
                },
                onEditQueuedMessage: { messageID in
                    viewModel.editQueuedMessage(id: messageID)
                },
                onDismissQueuedMessage: { messageID in
                    viewModel.removeQueuedMessage(id: messageID)
                },
                workingDirectory: workingDirectory,
                loadFileCompletions: loadFileCompletions,
                loadSkillCompletions: loadSkillCompletions,
                focusRequestToken: $focusRequestToken,
                showsActionRow: !usesNativeActionRow
            )
            .onChange(of: viewModel.state.inputDraft) { _, newValue in
                viewModel.cancelSessionHandoffSteeringCountdownIfDraftChanged(to: newValue)
                viewModel.cancelSessionHandoffCountdownIfDraftChanged(to: newValue)
            }
        }
    }
}

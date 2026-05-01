import AppKit
import SwiftUI

private enum ChatComposerPanelLayout {
    static let horizontalPadding = EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 21)
    static let verticalPadding: CGFloat = 0
    static let topContentSpacing: CGFloat = 8
    // This is the visible top/bottom clearance inside the composer panel.
    // Keep panel vertical padding at zero so it does not stack with this inset.
    static let inputOuterPadding = EdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0)
    static let inputOuterPaddingWithTopContent = EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 0)
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

    private var hasTopContent: Bool {
        viewModel.lastTurnError != nil ||
            viewModel.sessionContinuityNotice != nil ||
            viewModel.stagedContext != nil
    }

    private var inputOuterPadding: EdgeInsets {
        hasTopContent ? ChatComposerPanelLayout.inputOuterPaddingWithTopContent : ChatComposerPanelLayout.inputOuterPadding
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
                focusRequestToken: $focusRequestToken
            )
            .onChange(of: viewModel.state.inputDraft) { _, newValue in
                viewModel.cancelSessionHandoffSteeringCountdownIfDraftChanged(to: newValue)
                viewModel.cancelSessionHandoffCountdownIfDraftChanged(to: newValue)
            }
        }
        .padding(.top, hasTopContent ? ChatComposerPanelLayout.topContentSpacing : 0)
        .padding(ChatComposerPanelLayout.horizontalPadding)
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

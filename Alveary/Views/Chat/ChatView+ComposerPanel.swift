import AppKit
import SwiftUI

private let composerPanelHorizontalPadding: CGFloat = 20
private let composerPanelTopPadding: CGFloat = 10
private let composerPanelBottomPadding: CGFloat = 20

struct ChatComposerPanel: View {
    let viewModel: ConversationViewModel
    let composerCapabilities: ComposerCapabilities
    let workingDirectory: String?
    let showsTopDivider: Bool
    let showsCenteredPreHistoryRetry: Bool
    let composerMode: ComposerMode
    let composerIsBusy: Bool
    let selectedModel: Binding<String>
    let selectedEffort: Binding<String>
    let selectedPermissionMode: Binding<String>
    let selectedUseWorktree: Binding<Bool>
    let showWorktreePicker: Bool
    let sessionLocationLabel: String?
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
        let modelSupported = Set(AppSettings.supportedEffortLevels(forModel: selectedModel.wrappedValue))
        return composerCapabilities.supportedEffortLevels.filter(modelSupported.contains)
    }

    var body: some View {
        VStack(spacing: 10) {
            if let lastTurnError = viewModel.lastTurnError,
               !showsCenteredPreHistoryRetry {
                InlineBanner(message: lastTurnError, severity: .error, autoDismissAfter: nil) {
                    viewModel.lastTurnError = nil
                }
            }

            if let sessionContinuityNotice = viewModel.sessionContinuityNotice {
                InlineBanner(message: sessionContinuityNotice, severity: .warning, autoDismissAfter: nil) {
                    viewModel.sessionContinuityNotice = nil
                }
            }

            if let stagedContext = viewModel.stagedContext {
                StagedContextBanner(context: stagedContext) {
                    viewModel.dismissStagedContext()
                }
            }

            ChatInputField(
                text: Bindable(viewModel.state).inputDraft,
                mode: composerMode,
                onSubmit: onSubmit,
                onSteer: onSteer,
                onStop: onStop,
                outerPadding: EdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0),
                selectedModel: selectedModel,
                selectedEffort: selectedEffort,
                selectedPermissionMode: selectedPermissionMode,
                selectedUseWorktree: selectedUseWorktree,
                supportedPermissionModes: composerCapabilities.supportedPermissionModes,
                supportedEffortLevels: visibleEffortLevels,
                showWorktreePicker: showWorktreePicker,
                sessionLocationLabel: sessionLocationLabel,
                supportsMidTurnSteering: composerCapabilities.supportsMidTurnSteering,
                queuedMessages: viewModel.messageQueue.pending,
                isTurnActive: viewModel.state.turnState.isActive,
                inFlightQueuedMessageID: viewModel.state.inFlightQueuedMessageID,
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
        }
        .padding(.horizontal, composerPanelHorizontalPadding)
        .padding(.top, composerPanelTopPadding)
        .padding(.bottom, composerPanelBottomPadding)
        .background {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.bar)

                if showsTopDivider {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(height: 1)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showsTopDivider)
    }
}

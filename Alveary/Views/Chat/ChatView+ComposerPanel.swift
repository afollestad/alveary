import SwiftUI

struct ChatComposerPanel: View {
    let viewModel: ConversationViewModel
    let diffViewModel: DiffViewerViewModel
    let composerCapabilities: ComposerCapabilities
    let workingDirectory: String?
    let showsCenteredPreHistoryRetry: Bool
    let composerMode: ComposerMode
    let composerIsBusy: Bool
    let canShowWriteEscalation: Bool
    let permissionEscalationLabel: String
    let selectedModel: Binding<String>
    let selectedEffort: Binding<String>
    let selectedPermissionMode: Binding<String>
    let loadFileCompletions: () async -> [String]
    let loadSkillCompletions: () async -> [Skill]
    let onSubmit: () -> Void
    let onSteer: () -> Void
    let onStop: () -> Void
    let onApplyPermissionModeChange: (String) -> Void
    @Bindable var appState: AppState

    var body: some View {
        VStack(spacing: 10) {
            if let lastTurnError = viewModel.lastTurnError,
               !showsCenteredPreHistoryRetry {
                InlineBanner(message: lastTurnError, severity: .error, autoDismissAfter: nil) {
                    viewModel.lastTurnError = nil
                }
            }

            if viewModel.state.isReconfiguringSession {
                ReconfigureStatusBanner(message: "Applying session changes...")
            }

            if let sessionContinuityNotice = viewModel.sessionContinuityNotice {
                InlineBanner(message: sessionContinuityNotice, severity: .warning, autoDismissAfter: nil) {
                    viewModel.sessionContinuityNotice = nil
                }
            }

            if viewModel.state.showPermissionBanner {
                PermissionBanner(
                    canEscalate: canShowWriteEscalation,
                    isActionDisabled: composerIsBusy || viewModel.state.isReconfiguringSession,
                    escalationLabel: permissionEscalationLabel,
                    onDismiss: {
                        viewModel.state.showPermissionBanner = false
                    },
                    onEscalate: {
                        if let escalationMode = composerCapabilities.suggestedWriteEscalationMode {
                            onApplyPermissionModeChange(escalationMode)
                        }
                    }
                )
            }

            if let stagedContext = viewModel.stagedContext {
                StagedContextBanner(context: stagedContext) {
                    viewModel.dismissStagedContext()
                }
            }

            if !diffViewModel.files.isEmpty {
                ChangedFilesStrip(
                    files: diffViewModel.files,
                    onOpenDiff: { file in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            appState.isRightPaneVisible = true
                        }
                        guard let directory = diffViewModel.activeDirectory else {
                            return
                        }
                        Task {
                            await diffViewModel.selectFile(file, in: directory)
                        }
                    }
                )
            }

            ChatInputField(
                text: Bindable(viewModel.state).inputDraft,
                mode: composerMode,
                onSubmit: onSubmit,
                onSteer: onSteer,
                onStop: onStop,
                selectedModel: selectedModel,
                selectedEffort: selectedEffort,
                selectedPermissionMode: selectedPermissionMode,
                supportedPermissionModes: composerCapabilities.supportedPermissionModes,
                supportedEffortLevels: composerCapabilities.supportedEffortLevels,
                supportsMidTurnSteering: composerCapabilities.supportsMidTurnSteering,
                workingDirectory: workingDirectory,
                loadFileCompletions: loadFileCompletions,
                loadSkillCompletions: loadSkillCompletions
            )
        }
        .padding(20)
        .background(.bar)
    }
}

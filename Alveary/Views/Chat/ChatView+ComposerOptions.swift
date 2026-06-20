extension ChatView {
    var composerPresentation: ComposerPresentation {
        ComposerPresentation(
            text: viewModel.state.inputDraft,
            isTextEffectivelyEmpty: viewModel.state.inputDraftIsEffectivelyEmpty,
            mode: composerMode,
            defaultEnterBehavior: defaultEnterBehavior,
            supportsMidTurnSteering: composerCapabilities.supportsMidTurnSteering,
            canSteerCurrentTurn: viewModel.canSteerCurrentTurn,
            isHandoffSteeringPromptActive: viewModel.state.isAwaitingHandoffSteering,
            isHandoffOutputPromptActive: viewModel.state.pendingHandoffOutput != nil,
            handoffSteeringCountdown: viewModel.state.handoffSteeringCountdownRemaining,
            sendCountdown: viewModel.state.handoffCountdownRemaining,
            isProjectTrustBlocked: isProjectTrustBlocked
        )
    }

    var localCommandAvailability: ComposerLocalCommandAvailability {
        guard !viewModel.state.hasActiveSessionHandoff else {
            return ComposerLocalCommandAvailability()
        }

        return ComposerLocalCommandAvailability(
            supportsPlanMode: composerCapabilities.supportsPlanMode,
            supportsSpeedMode: composerCapabilities.supportsSpeedMode,
            supportsSessionHandoff: true
        )
    }

    var passthroughSlashCommands: [ComposerPassthroughSlashCommand] {
        guard providerID == "claude",
              !viewModel.state.hasActiveSessionHandoff else {
            return []
        }

        return [
            ComposerPassthroughSlashCommand(
                command: "compact",
                subtitle: "Compact context",
                detailText: "Claude",
                uri: "alveary://provider-commands/claude/compact",
                argumentHint: "Optional compact instructions"
            )
        ]
    }

    var canUseOutboundComposerActions: Bool {
        if isProjectTrustBlocked {
            return false
        }
        switch composerMode {
        case .idle, .busy(canStop: true):
            return true
        case .busy(canStop: false), .progressOnly:
            return false
        }
    }

    var showWorktreePicker: Bool {
        threadPresentation.showWorktreePicker
    }

    func clearSubmittedDraftAndRequestFocus(source: ComposerDraftSource) {
        viewModel.clearInputDraft(source: source)
        appState.requestComposerFocus()
    }

}

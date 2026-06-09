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
            supportsSessionHandoff: viewModel.settingsService.current.sessionHandoffCommandEnabled
        )
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

    var sessionLocationLabel: String? {
        threadPresentation.sessionLocationLabel
    }

    func clearSubmittedDraftAndRequestFocus(source: ComposerDraftSource) {
        viewModel.clearInputDraft(source: source)
        appState.requestComposerFocus()
    }

}

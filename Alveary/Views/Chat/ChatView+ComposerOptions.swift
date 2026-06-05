extension ChatView {
    var composerPresentation: ComposerPresentation {
        ComposerPresentation(
            text: viewModel.state.inputDraft,
            isTextEffectivelyEmpty: viewModel.state.inputDraftIsEffectivelyEmpty,
            mode: composerMode,
            defaultEnterBehavior: defaultEnterBehavior,
            supportsMidTurnSteering: composerCapabilities.supportsMidTurnSteering,
            isHandoffSteeringPromptActive: viewModel.state.isAwaitingHandoffSteering,
            isHandoffOutputPromptActive: viewModel.state.pendingHandoffOutput != nil,
            handoffSteeringCountdown: viewModel.state.handoffSteeringCountdownRemaining,
            sendCountdown: viewModel.state.handoffCountdownRemaining,
            isProjectTrustBlocked: isProjectTrustBlocked
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

    var showsProviderPicker: Bool {
        guard let thread = conversation.thread,
              !thread.hasCompletedInitialSetup,
              viewModel.setupPhase == nil,
              !viewModel.state.isSendingMessage,
              !viewModel.state.isCancellingInitialSetup else {
            return false
        }
        return true
    }

    var sessionLocationLabel: String? {
        threadPresentation.sessionLocationLabel
    }

    func clearSubmittedDraftAndRequestFocus(source: ComposerDraftSource) {
        viewModel.clearInputDraft(source: source)
        appState.requestComposerFocus()
    }

}

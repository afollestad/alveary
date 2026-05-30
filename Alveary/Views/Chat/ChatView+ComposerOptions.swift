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

    func clearSubmittedDraftAndRequestFocus(source: ComposerDraftSource) {
        viewModel.clearInputDraft(source: source)
        appState.requestComposerFocus()
    }

    var visibleEffortLevels: [String] {
        ComposerSettingsPresentation.visibleEffortLevels(
            selectedModel: selectedModelBinding.wrappedValue,
            providerSupportedEffortLevels: composerCapabilities.supportedEffortLevels
        )
    }

    var composerModelOptions: [String] {
        let selectedModel = selectedModelBinding.wrappedValue
        let knownModels = AppSettings.supportedModels
        return knownModels.contains(selectedModel) ? knownModels : knownModels + [selectedModel]
    }
}

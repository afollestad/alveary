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

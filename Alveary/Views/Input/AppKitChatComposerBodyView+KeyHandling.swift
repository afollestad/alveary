import Foundation

extension AppKitChatComposerBodyView {
    func handleKeyPress(_ keyPress: AppTextEditorKeyPress) -> AppTextEditorKeyPress.Result {
        if handleAutocompleteKeyPress(keyPress) {
            return .handled
        }
        if handleStopShortcutKeyPress(keyPress) {
            return .handled
        }
        guard let configuration,
              keyPress.key == .return else {
            return .ignored
        }
        if keyPress.modifiers.contains(.shift) {
            return .ignored
        }

        switch configuration.mode {
        case .progressOnly:
            return .handled
        case .busy(let canStop):
            performBusyReturnAction(
                canStop: canStop,
                usesAlternateBehavior: keyPress.modifiers.contains(.command),
                configuration: configuration
            )
            return .handled
        case .idle:
            performSubmit(configuration: configuration)
            return .handled
        }
    }

    func performBusyReturnAction(
        canStop: Bool,
        usesAlternateBehavior: Bool,
        configuration: AppKitChatComposerBodyConfiguration
    ) {
        guard canStop, configuration.supportsMidTurnSteering else {
            performSubmit(configuration: configuration)
            return
        }
        switch presentation(for: configuration).busyReturnAction(usesAlternateBehavior: usesAlternateBehavior) {
        case .submit:
            performSubmit(configuration: configuration)
        case .steer:
            performSteer(configuration: configuration)
        }
    }

    func performSubmit(configuration: AppKitChatComposerBodyConfiguration) {
        guard presentation(for: configuration).canSubmit else {
            return
        }
        configuration.onSubmit()
    }

    func performSteer(configuration: AppKitChatComposerBodyConfiguration) {
        guard presentation(for: configuration).canSteer else {
            return
        }
        configuration.onSteer()
    }

    func performStop(configuration: AppKitChatComposerBodyConfiguration) {
        clearStopConfirmation(configuration: configuration)
        configuration.onStop()
    }

    func handleStopShortcutKeyPress(_ keyPress: AppTextEditorKeyPress) -> Bool {
        guard let configuration else {
            return false
        }
        switch ChatInputStopConfirmationDecision.resolve(
            keyPress: keyPress,
            canUseEscapeToStop: presentation(for: configuration).canUseEscapeToStop,
            isConfirmationArmed: configuration.isStopConfirmationArmed
        ) {
        case .ignored:
            return false
        case .confirmStop:
            performStop(configuration: configuration)
        case .armConfirmation:
            armStopConfirmation(configuration: configuration)
        }
        return true
    }

    func armStopConfirmation(configuration: AppKitChatComposerBodyConfiguration) {
        stopConfirmationResetTask?.cancel()
        configuration.onStopConfirmationChange(true)
        stopConfirmationResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.stopConfirmationTimeoutNanoseconds)
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                guard let self,
                      let configuration = self.configuration,
                      ChatInputStopConfirmationDecision.shouldClearAfterConfirmationTimeout(configuration.isStopConfirmationArmed) else {
                    return
                }
                self.clearStopConfirmation(configuration: configuration)
            }
        }
    }

    func clearStopConfirmation(configuration: AppKitChatComposerBodyConfiguration) {
        stopConfirmationResetTask?.cancel()
        stopConfirmationResetTask = nil
        guard configuration.isStopConfirmationArmed else {
            return
        }
        configuration.onStopConfirmationChange(false)
    }
}

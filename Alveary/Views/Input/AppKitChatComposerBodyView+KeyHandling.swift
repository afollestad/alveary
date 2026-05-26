import Foundation

extension AppKitChatComposerBodyView {
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
                      configuration.isStopConfirmationArmed else {
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

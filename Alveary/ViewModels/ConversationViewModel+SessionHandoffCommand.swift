import Foundation

extension ConversationViewModel {
    func canUseSessionHandoff(
        trigger: SessionHandoffTrigger,
        retryingFailedHandoff: Bool
    ) -> Bool {
        let settings = settingsService.current
        switch trigger {
        case .automatic:
            return settings.contextManagementEnabled
        case .command:
            return settings.sessionHandoffCommandEnabled
        case .manual:
            return retryingFailedHandoff || settings.contextManagementEnabled || settings.sessionHandoffCommandEnabled
        }
    }

    @discardableResult
    func triggerSessionHandoffFromCommand(steeringPrompt: String? = nil) -> Bool {
        guard canStartSessionHandoff(trigger: .command, retryingFailedHandoff: false) else { return false }

        Task { @MainActor [self] in
            if let steeringPrompt, !steeringPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.submittedHandoffSteeringPrompt = steeringPrompt
                await startHiddenSessionHandoff()
            } else {
                await startSessionHandoff(trigger: .command)
            }
        }
        return true
    }
}

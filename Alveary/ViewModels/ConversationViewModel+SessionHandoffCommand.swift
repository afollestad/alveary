import Foundation

extension ConversationViewModel {
    func canUseSessionHandoff(trigger: SessionHandoffTrigger) -> Bool {
        let settings = settingsService.current
        switch trigger {
        case .automatic:
            return settings.contextManagementEnabled
        case .command, .manual:
            return true
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

import Foundation

enum SessionHandoffTrigger: Sendable {
    case automatic
    case debugAutomatic
    case command
    case manual
}

extension ConversationViewModel {
    func markSessionHandoffAccepted(capturedPlanModeEnabled: Bool? = nil) {
        state.sessionHandoffStartedInPlanMode = capturedPlanModeEnabled ?? effectivePlanModeEnabled
    }

    func canUseSessionHandoff(trigger: SessionHandoffTrigger) -> Bool {
        let settings = settingsService.current
        switch trigger {
        case .automatic:
            return settings.contextManagementEnabled
        case .debugAutomatic, .command, .manual:
            return true
        }
    }

    @discardableResult
    func triggerSessionHandoffFromCommand(steeringPrompt: String? = nil) -> Bool {
        guard canStartSessionHandoff(trigger: .command, retryingFailedHandoff: false) else { return false }

        let capturedPlanModeEnabled = effectivePlanModeEnabled
        let submittedSteeringPrompt = steeringPrompt.flatMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
        }
        if submittedSteeringPrompt != nil {
            markSessionHandoffAccepted(capturedPlanModeEnabled: capturedPlanModeEnabled)
            appendSessionHandoffStartedNote()
        }
        Task { @MainActor [self] in
            if let submittedSteeringPrompt {
                state.submittedHandoffSteeringPrompt = submittedSteeringPrompt
                await startHiddenSessionHandoff()
            } else {
                await startSessionHandoff(trigger: .command, capturedPlanModeEnabled: capturedPlanModeEnabled)
            }
        }
        return true
    }

    @discardableResult
    func triggerAutomaticSessionHandoffFromDebugMenu() -> Bool {
        guard canStartSessionHandoff(trigger: .debugAutomatic, retryingFailedHandoff: false) else { return false }

        let capturedPlanModeEnabled = effectivePlanModeEnabled
        Task { @MainActor [self] in
            await startSessionHandoff(trigger: .debugAutomatic, capturedPlanModeEnabled: capturedPlanModeEnabled)
        }
        return true
    }
}

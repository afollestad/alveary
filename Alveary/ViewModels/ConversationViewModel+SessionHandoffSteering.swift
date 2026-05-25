import Foundation

extension ConversationViewModel {
    var sessionHandoffSteeringCountdownTask: Task<Void, Never>? {
        get { state.sessionHandoffSteeringCountdownTask }
        set { state.sessionHandoffSteeringCountdownTask = newValue }
    }

    func cancelSessionHandoffSteeringCountdownIfDraftChanged(to newDraft: String) {
        guard state.isAwaitingHandoffSteering,
              let baseline = state.handoffSteeringDraftBaseline,
              state.handoffSteeringCountdownRemaining != nil,
              newDraft != baseline else {
            return
        }

        cancelSessionHandoffSteeringCountdown()
    }

    @discardableResult
    func submitSessionHandoffSteeringPrompt(_ prompt: String) -> Bool {
        guard state.isAwaitingHandoffSteering else {
            return false
        }

        cancelSessionHandoffSteeringCountdown()
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        state.submittedHandoffSteeringPrompt = trimmedPrompt.isEmpty ? nil : prompt
        state.isAwaitingHandoffSteering = false
        state.isHandingOffSession = true
        clearInputDraft()

        Task { @MainActor [self] in
            await startHiddenSessionHandoff()
        }
        return true
    }

    func autoSubmitSessionHandoffSteeringPromptIfUnedited() async {
        let draft = flushDraftFromEditor()
        guard state.isAwaitingHandoffSteering,
              state.handoffSteeringCountdownRemaining == 0,
              let baseline = state.handoffSteeringDraftBaseline,
              draft.text == baseline else {
            return
        }

        submitSessionHandoffSteeringPrompt("")
    }

    func shouldRequestHandoffSteering(
        trigger: SessionHandoffTrigger,
        retryingFailedHandoff: Bool
    ) -> Bool {
        trigger == .automatic &&
            !retryingFailedHandoff &&
            settingsService.current.handoffSteeringEnabled
    }

    func beginSessionHandoffSteeringPrompt() {
        sessionHandoffCountdownTask?.cancel()
        sessionHandoffCountdownTask = nil
        sessionHandoffSteeringCountdownTask?.cancel()
        sessionHandoffSteeringCountdownTask = nil
        state.isAwaitingHandoffSteering = true
        state.isHandingOffSession = false
        state.hiddenHandoffResponse = ""
        state.pendingHandoffOutput = nil
        state.failedSessionHandoffMessage = nil
        state.handoffCountdownRemaining = nil
        state.handoffDraftBaseline = nil
        state.submittedHandoffSteeringPrompt = nil
        let draft = flushDraftFromEditor()
        state.sessionHandoffRestorableDraft = draft.text
        state.sessionHandoffRestorableDraftSource = draft.source
        state.handoffSteeringDraftBaseline = ""
        clearInputDraft(source: draft.source)
        state.lastTurnInterrupted = false
        state.isCancellingTurn = false
        state.lastTurnError = nil
        state.sessionContinuityNotice = nil
        startSessionHandoffSteeringCountdown()
    }

    func startSessionHandoffSteeringCountdown() {
        state.handoffSteeringCountdownRemaining = AppSettings.normalizedHandoffSteeringCountdownSeconds(
            settingsService.current.handoffSteeringCountdownSeconds
        )
        sessionHandoffSteeringCountdownTask?.cancel()
        sessionHandoffSteeringCountdownTask = Task { @MainActor [self] in
            while let remaining = state.handoffSteeringCountdownRemaining, remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else {
                    return
                }
                guard let currentRemaining = state.handoffSteeringCountdownRemaining else {
                    return
                }
                state.handoffSteeringCountdownRemaining = max(currentRemaining - 1, 0)
            }

            await autoSubmitSessionHandoffSteeringPromptIfUnedited()
        }
    }

    func cancelSessionHandoffSteeringCountdown() {
        sessionHandoffSteeringCountdownTask?.cancel()
        sessionHandoffSteeringCountdownTask = nil
        state.handoffSteeringCountdownRemaining = nil
        state.handoffSteeringDraftBaseline = nil
    }
}

import Foundation
import OSLog
import SwiftData

private let sessionHandoffLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Alveary", category: "SessionHandoff")

extension ConversationViewModel {
    func startSessionHandoff(
        trigger: SessionHandoffTrigger,
        retryingFailedHandoff: Bool = false,
        capturedPlanModeEnabled: Bool? = nil
    ) async {
        guard canStartSessionHandoff(trigger: trigger, retryingFailedHandoff: retryingFailedHandoff) else {
            return
        }

        markSessionHandoffAccepted(capturedPlanModeEnabled: capturedPlanModeEnabled)
        appendSessionHandoffStartedNote()
        clearRestorableDraftForEmptyRetryIfNeeded(retryingFailedHandoff: retryingFailedHandoff)
        if shouldRequestHandoffSteering(trigger: trigger, retryingFailedHandoff: retryingFailedHandoff) {
            beginSessionHandoffSteeringPrompt(startsCountdown: trigger == .automatic || trigger == .debugAutomatic)
            return
        }

        preserveVisibleDraftForPromptedHandoffIfNeeded(trigger: trigger, retryingFailedHandoff: retryingFailedHandoff)
        await startHiddenSessionHandoff()
    }

    func startHiddenSessionHandoff() async {
        sessionHandoffCountdownTask?.cancel()
        sessionHandoffCountdownTask = nil
        sessionHandoffSteeringCountdownTask?.cancel()
        sessionHandoffSteeringCountdownTask = nil
        clearPendingExitPlanModeDenialState()
        state.isAutomaticSessionHandoffPending = false
        stashVisibleDraftForHandoffIfNeeded()
        state.isAwaitingHandoffSteering = false
        state.handoffSteeringCountdownRemaining = nil
        state.handoffSteeringDraftBaseline = nil
        state.isHandingOffSession = true
        state.hiddenHandoffResponse = ""
        state.pendingHandoffOutput = nil
        state.failedSessionHandoffMessage = nil
        state.handoffCountdownRemaining = nil
        state.handoffDraftBaseline = nil
        state.lastTurnInterrupted = false
        state.isCancellingTurn = false
        state.lastTurnError = nil
        state.sessionContinuityNotice = nil
        state.activeRuntimeActivityTurnId = nil
        do {
            if await needsRespawn() {
                try await startAgentReserved(config: makeSpawnConfig(settingsSource: .currentContinuation))
                state.sessionContinuityNotice = nil
                state.respawnAttempts = 0
            }

            try await agentsManager.sendMessage(makeHiddenSessionHandoffPrompt(), conversationId: conversation.id, activityVisibility: .hidden)
            beginHiddenActivityTurn()
        } catch {
            failSessionHandoff("Session handoff failed: \(error.localizedDescription)")
        }
    }

    // Hidden handoff events drive fresh-session setup, but never transcript rows.
    // swiftlint:disable:next cyclomatic_complexity
    func shouldPersistHiddenSessionHandoffEvent(_ event: ConversationEvent) -> Bool {
        if state.failedSessionHandoffMessage != nil, !state.isHandingOffSession {
            return acknowledgeLateHiddenSessionHandoffTerminalEvent(event)
        }

        switch event {
        case .sessionInit:
            return false
        case .permissionModeChanged(let permissionMode):
            syncRuntimePermissionMode(permissionMode)
            return false
        case .messageChunk(let text, let parentToolUseId):
            guard parentToolUseId == nil else {
                return false
            }
            state.clearStreamingText()
            state.hiddenHandoffResponse.append(text)
            sessionHandoffLogger.debug(
                "Hidden handoff chunk length=\(text.count) totalLength=\(self.state.hiddenHandoffResponse.count)"
            )
            return false
        case .message(let role, let content, _):
            if role == "assistant" {
                state.clearStreamingText()
                if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    state.hiddenHandoffResponse = content
                    sessionHandoffLogger.debug("Hidden handoff assistant message captured length=\(content.count)")
                } else {
                    sessionHandoffLogger.debug(
                        "Hidden handoff ignored empty assistant message existingLength=\(self.state.hiddenHandoffResponse.count)"
                    )
                }
            }
            return false
        case .tokens:
            if let payload = TokenEventPayload(event) {
                handleHiddenSessionHandoffTokens(payload)
            }
            return false
        case .runtimeActivity(let activityState, let turnId, let outcome):
            return handleHiddenSessionHandoffRuntimeActivity(state: activityState, turnId: turnId, outcome: outcome)
        case .toolApprovalRequested, .toolApprovalFailed:
            failSessionHandoff("Session handoff paused because the hidden handoff prompt requested approval.")
            return false
        case .error(let message):
            return failHiddenSessionHandoffFromError(message)
        default:
            return false
        }
    }

    func cancelSessionHandoffCountdownIfDraftChanged(to newDraft: String) {
        guard let baseline = state.handoffDraftBaseline,
              state.handoffCountdownRemaining != nil,
              newDraft != baseline else {
            return
        }

        cancelSessionHandoffCountdown(clearPendingOutput: false)
    }

    func cancelSessionHandoffCountdownForEditorMutation() {
        guard state.handoffCountdownRemaining != nil else {
            return
        }

        cancelSessionHandoffCountdown(clearPendingOutput: false)
    }

    @discardableResult
    func prepareManualSessionHandoffSendIfNeeded() -> Bool {
        guard state.handoffCountdownRemaining != nil || state.pendingHandoffOutput != nil else {
            return false
        }
        cancelSessionHandoffCountdown(clearPendingOutput: true)
        return true
    }

    var canRetryFailedSessionHandoff: Bool {
        state.failedSessionHandoffMessage != nil
    }

    func failHiddenSessionHandoff(_ message: String) { failSessionHandoff(message) }

    func finishHiddenSessionHandoff(with output: String) async { await finishSessionHandoff(with: output) }

    func retryFailedSessionHandoff() {
        guard state.failedSessionHandoffMessage != nil else {
            return
        }

        Task { @MainActor [self] in
            await startSessionHandoff(trigger: .manual, retryingFailedHandoff: true)
        }
    }

    func autoSendSessionHandoffOutputIfUnedited() async {
        let draft = flushDraftFromEditor()
        guard state.handoffCountdownRemaining == 0,
              let baseline = state.handoffDraftBaseline,
              draft.text == baseline else {
            return
        }

        let output = draft.text
        clearSessionHandoffCountdownState(clearPendingOutput: true)
        state.failedSessionHandoffMessage = nil
        clearInputDraft(source: draft.source)
        let retryableMessageCount = state.retryableFailedMessageIDs.count
        do {
            try await sendSessionHandoffOutput(output)
        } catch {
            if state.retryableFailedMessageIDs.count == retryableMessageCount {
                replaceInputDraft(output, source: draft.source)
            }
            state.lastTurnError = "Session handoff send failed: \(error.localizedDescription)"
        }
    }

    func sendSessionHandoffOutput(_ output: String) async throws {
        let retryableMessageCount = state.retryableFailedMessageIDs.count
        do {
            try await withOutboundReservation {
                try await deliverMessageReserved(makeSessionHandoffOutgoingMessage(output: output))
            }
            restoreSessionHandoffDraftIfNeeded()
            clearSubmittedHandoffSteering()
        } catch {
            if state.retryableFailedMessageIDs.count == retryableMessageCount {
                state.pendingHandoffOutput = output
            }
            throw error
        }
    }
}

extension ConversationViewModel {
    var sessionHandoffCountdownTask: Task<Void, Never>? {
        get { state.sessionHandoffCountdownTask }
        set { state.sessionHandoffCountdownTask = newValue }
    }

    func canStartSessionHandoff(
        trigger: SessionHandoffTrigger,
        retryingFailedHandoff: Bool
    ) -> Bool {
        guard canUseSessionHandoff(trigger: trigger) else { return false }
        let hasBlockingHandoff = state.isHandingOffSession ||
            state.isAwaitingHandoffSteering ||
            state.pendingHandoffOutput != nil ||
            state.handoffCountdownRemaining != nil ||
            (!retryingFailedHandoff && state.failedSessionHandoffMessage != nil)
        let canClearQueuedPlanRevision = trigger == .manual && state.messageQueue.pending.contains { $0.consumedExitPlanModeRevisionGuidance != nil }
        guard !needsSetup else {
            state.lastTurnError = "Complete the first turn before triggering a session handoff."
            return false
        }
        guard !hasBlockingHandoff,
              !state.turnState.isActive,
              !state.isSendingMessage,
              !state.isReconfiguringSession,
              state.pendingToolApproval == nil,
              !hasUnansweredPrompt || canClearQueuedPlanRevision else {
            if trigger != .automatic {
                state.lastTurnError = "Wait for the current conversation action to finish before triggering session handoff."
            }
            return false
        }
        return true
    }

}

private extension ConversationViewModel {
    func makeHiddenSessionHandoffPrompt() -> String {
        SessionHandoffPromptBuilder.hiddenPrompt(
            configuredPrompt: settingsService.current.sessionHandoffPrompt,
            steeringPrompt: state.submittedHandoffSteeringPrompt,
            isSteeringEnabled: shouldIncludeSubmittedHandoffSteering,
            isPlanModeHandoff: state.sessionHandoffStartedInPlanMode
        )
    }

    func makeSessionHandoffOutgoingMessage(output: String) -> String {
        SessionHandoffPromptBuilder.outgoingMessage(
            handoffOutput: output,
            steeringPrompt: state.submittedHandoffSteeringPrompt,
            isSteeringEnabled: shouldIncludeSubmittedHandoffSteering
        )
    }

    var shouldIncludeSubmittedHandoffSteering: Bool {
        settingsService.current.handoffSteeringEnabled || state.submittedHandoffSteeringPrompt != nil
    }

    func handleHiddenSessionHandoffTokens(_ payload: TokenEventPayload) {
        state.clearStreamingText()
        sessionHandoffLogger.debug(
            """
            Hidden handoff tokens stopReason=\(payload.stopReason ?? "nil") \
            isError=\(payload.isError) denials=\(payload.permissionDenials.count) \
            responseLength=\(self.state.hiddenHandoffResponse.count)
            """
        )
        guard payload.stopReason != ConversationEvent.interimUsageStopReason else {
            return
        }
        guard payload.completesTurn else { return }
        guard !payload.isError, payload.permissionDenials.isEmpty else {
            state.turnState.endTurn()
            failSessionHandoff(ConversationErrorDisplayPolicy.sessionHandoffTokenFailureMessage(stopReason: payload.stopReason))
            return
        }

        let output = SessionHandoffPromptBuilder.editableHandoffOutput(state.hiddenHandoffResponse)
        guard !output.isEmpty else {
            state.turnState.endTurn()
            failSessionHandoff("Session handoff failed: the hidden handoff prompt returned no context.")
            return
        }

        sessionHandoffLogger.debug("Hidden handoff completed with outputLength=\(output.count)")
        state.turnState.endTurn()
        Task { @MainActor [self] in
            await finishSessionHandoff(with: output)
        }
    }

    func finishSessionHandoff(with output: String) async {
        let pendingSettings = state.pendingSessionSettingsChange
        do {
            let config = try makeSpawnConfig(settingsSource: .nextTurn)
            await flushPendingSaveIfNeeded()
            await prepareForSpawn(config: config)
            try await agentsManager.startFreshSession(conversationId: conversation.id, config: config)
            finishFreshSessionSettingsApply(pending: pendingSettings, config: config)
            state.sessionContinuityNotice = nil
            resetSubscriptionTrackingForNewSession()
            subscribe()
            recordContextWindowInvalidation()
            completeSessionHandoffNote()

            if shouldCustomizeSessionHandoffOutput {
                beginSessionHandoffCustomization(output: output)
            } else {
                await sendSessionHandoffOutputImmediately(output)
            }
        } catch {
            if let pendingSettings {
                rollbackPendingSessionSettings(pendingSettings)
            }
            await resubscribeIfActiveRuntimeIsRunning()
            failSessionHandoff("Session handoff failed: \(error.localizedDescription)")
        }
    }

    func beginSessionHandoffCustomization(output: String) {
        state.isHandingOffSession = false
        state.hiddenHandoffResponse = ""
        state.pendingHandoffOutput = output
        state.failedSessionHandoffMessage = nil
        state.lastTurnError = nil
        state.handoffDraftBaseline = output
        replaceInputDraft(output)
        sessionHandoffLogger.debug("Hidden handoff output staged for customization length=\(output.count)")
        startSessionHandoffCountdown()
    }

    func sendSessionHandoffOutputImmediately(_ output: String) async {
        state.isHandingOffSession = false
        state.hiddenHandoffResponse = ""
        state.pendingHandoffOutput = nil
        state.failedSessionHandoffMessage = nil
        state.lastTurnError = nil
        state.handoffDraftBaseline = nil
        state.handoffCountdownRemaining = nil
        let retryableMessageCount = state.retryableFailedMessageIDs.count
        do {
            try await sendSessionHandoffOutput(output)
        } catch {
            if state.retryableFailedMessageIDs.count == retryableMessageCount {
                replaceInputDraft(output)
            }
            state.lastTurnError = "Session handoff send failed: \(error.localizedDescription)"
        }
    }

    func startSessionHandoffCountdown() {
        state.handoffCountdownRemaining = promptSendCountdownSeconds
        sessionHandoffCountdownTask?.cancel()
        sessionHandoffCountdownTask = Task { @MainActor [self] in
            while let remaining = state.handoffCountdownRemaining, remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else {
                    return
                }
                guard let currentRemaining = state.handoffCountdownRemaining else {
                    return
                }
                state.handoffCountdownRemaining = max(currentRemaining - 1, 0)
            }

            await autoSendSessionHandoffOutputIfUnedited()
        }
    }

    func cancelSessionHandoffCountdown(clearPendingOutput: Bool) {
        sessionHandoffCountdownTask?.cancel()
        clearSessionHandoffCountdownState(clearPendingOutput: clearPendingOutput)
    }

    func clearSessionHandoffCountdownState(clearPendingOutput: Bool) {
        sessionHandoffCountdownTask = nil
        (state.handoffCountdownRemaining, state.handoffDraftBaseline) = (nil, nil)
        if clearPendingOutput { state.pendingHandoffOutput = nil }
    }

    var promptSendCountdownSeconds: Int {
        AppSettings.normalizedHandoffPromptSendCountdownSeconds(
            settingsService.current.handoffPromptSendCountdownSeconds
        )
    }

    var shouldCustomizeSessionHandoffOutput: Bool {
        settingsService.current.handoffContextCustomizationEnabled &&
            promptSendCountdownSeconds > 0
    }

    func failSessionHandoff(_ message: String) {
        sessionHandoffLogger.error("Hidden handoff failed: \(message, privacy: .public)")
        sessionHandoffCountdownTask?.cancel()
        sessionHandoffCountdownTask = nil
        sessionHandoffSteeringCountdownTask?.cancel()
        sessionHandoffSteeringCountdownTask = nil
        let restorableDraft = state.sessionHandoffRestorableDraft
        state.isAwaitingHandoffSteering = false
        state.isHandingOffSession = false
        state.hiddenHandoffResponse = ""
        state.pendingHandoffOutput = nil
        state.failedSessionHandoffMessage = message
        state.handoffSteeringCountdownRemaining = nil
        state.handoffSteeringDraftBaseline = nil
        state.handoffCountdownRemaining = nil
        state.handoffDraftBaseline = nil
        state.sessionHandoffStartedInPlanMode = false
        removeSessionHandoffStartedNoteIfNeeded()
        state.clearStreamingText()
        state.activeRuntimeActivityTurnId = nil
        state.turnState.endTurn()
        state.lastTurnError = message
        let draft = flushDraftFromEditor()
        if let restorableDraft, draft.text.isEmpty {
            replaceInputDraft(restorableDraft, source: state.sessionHandoffRestorableDraftSource)
        }
    }

    func clearSubmittedHandoffSteering() {
        state.submittedHandoffSteeringPrompt = nil
        state.sessionHandoffRestorableDraft = nil
        state.sessionHandoffStartedInPlanMode = false
        state.sessionHandoffNoteRecordID = nil
    }

    func clearRestorableDraftForEmptyRetryIfNeeded(retryingFailedHandoff: Bool) {
        let draft = flushDraftFromEditor()
        guard retryingFailedHandoff,
              state.sessionHandoffRestorableDraft != nil,
              draft.text.isEmpty else {
            return
        }

        state.sessionHandoffRestorableDraft = nil
    }

    func preserveVisibleDraftForPromptedHandoffIfNeeded(
        trigger: SessionHandoffTrigger,
        retryingFailedHandoff: Bool
    ) {
        let draft = flushDraftFromEditor()
        let shouldPreserveDraft = trigger == .automatic || trigger == .debugAutomatic || trigger == .command
        guard shouldPreserveDraft,
              !retryingFailedHandoff,
              !draft.text.isEmpty else {
            return
        }

        state.sessionHandoffRestorableDraft = draft.text
        state.sessionHandoffRestorableDraftSource = draft.source
    }

    func stashVisibleDraftForHandoffIfNeeded() {
        let hasSubmittedSteeringOrRestorableDraft = state.submittedHandoffSteeringPrompt != nil ||
            state.sessionHandoffRestorableDraft != nil
        let draft = flushDraftFromEditor()
        guard hasSubmittedSteeringOrRestorableDraft,
              !draft.text.isEmpty else {
            return
        }

        state.sessionHandoffRestorableDraft = draft.text
        state.sessionHandoffRestorableDraftSource = draft.source
        clearInputDraft(source: draft.source)
    }

    func restoreSessionHandoffDraftIfNeeded() {
        let draft = flushDraftFromEditor()
        guard let restorableDraft = state.sessionHandoffRestorableDraft,
              draft.text.isEmpty else {
            return
        }

        replaceInputDraft(restorableDraft, source: state.sessionHandoffRestorableDraftSource)
    }

    func resetSubscriptionTrackingForNewSession() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        state.lastObservedEventIndex = 0
        state.lastPersistedEventIndex = 0
        state.activeBufferGeneration = nil
        state.activeSubscriptionToken = nil
        state.activeRuntimeActivityTurnId = nil
        state.grouper.resetInFlightStateForNewSession()
    }
}

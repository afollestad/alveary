import Foundation
import SwiftData

enum SessionHandoffTrigger: Sendable {
    case automatic
    case manual
}

extension ConversationViewModel {
    static let handoffSteeringPlaceholder = "Add steering for the session handoff, or submit empty to continue..."

    func triggerSessionHandoffFromCommand() {
        Task { @MainActor [self] in
            await startSessionHandoff(trigger: .manual)
        }
    }

    func startSessionHandoff(
        trigger: SessionHandoffTrigger,
        retryingFailedHandoff: Bool = false
    ) async {
        guard canStartSessionHandoff(trigger: trigger, retryingFailedHandoff: retryingFailedHandoff) else {
            return
        }

        clearRestorableDraftForEmptyRetryIfNeeded(retryingFailedHandoff: retryingFailedHandoff)
        if shouldRequestHandoffSteering(trigger: trigger, retryingFailedHandoff: retryingFailedHandoff) {
            beginSessionHandoffSteeringPrompt()
            return
        }

        preserveVisibleDraftForAutomaticHandoffIfNeeded(trigger: trigger, retryingFailedHandoff: retryingFailedHandoff)
        await startHiddenSessionHandoff()
    }

    func startHiddenSessionHandoff() async {
        sessionHandoffCountdownTask?.cancel()
        sessionHandoffCountdownTask = nil
        sessionHandoffSteeringCountdownTask?.cancel()
        sessionHandoffSteeringCountdownTask = nil
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

        do {
            if await needsRespawn() {
                try await startAgentReserved(config: makeSpawnConfig())
                state.sessionContinuityNotice = nil
                state.respawnAttempts = 0
            }

            try await agentsManager.sendMessage(makeHiddenSessionHandoffPrompt(), conversationId: conversation.id)
            state.turnState.beginTurn()
        } catch {
            failSessionHandoff("Session handoff failed: \(error.localizedDescription)")
        }
    }

    func shouldTriggerAutomaticSessionHandoff(for payload: TokenEventPayload) -> Bool {
        let settings = settingsService.current
        guard settings.contextManagementEnabled,
              !state.hasActiveSessionHandoff,
              !state.isSendingMessage,
              !state.isReconfiguringSession,
              state.pendingToolApproval == nil,
              !hasUnansweredPrompt,
              let contextWindowSize = payload.contextWindowSize,
              contextWindowSize > 0 else {
            return false
        }

        let contextUsedTokens = payload.input + payload.cacheRead + payload.cacheCreation
        let threshold = AppSettings.normalizedSessionHandoffWindowPercentage(
            settings.sessionHandoffWindowPercentage
        )
        return Double(contextUsedTokens) / Double(contextWindowSize) * 100 >= Double(threshold)
    }

    // Hidden handoff events drive fresh-session setup, but never transcript rows.
    // swiftlint:disable:next cyclomatic_complexity
    func shouldPersistHiddenSessionHandoffEvent(_ event: ConversationEvent) -> Bool {
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
            return false
        case .message(let role, let content, _):
            if role == "assistant" {
                state.clearStreamingText()
                state.hiddenHandoffResponse = content
            }
            return false
        case .tokens:
            if let payload = TokenEventPayload(event) {
                handleHiddenSessionHandoffTokens(payload)
            }
            return false
        case .toolApprovalRequested, .toolApprovalFailed:
            failSessionHandoff("Session handoff paused because the hidden handoff prompt requested approval.")
            return false
        case .error(let message):
            failSessionHandoff("Session handoff failed: \(message)")
            return false
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

    func retryFailedSessionHandoff() {
        guard state.failedSessionHandoffMessage != nil else {
            return
        }

        Task { @MainActor [self] in
            await startSessionHandoff(trigger: .manual, retryingFailedHandoff: true)
        }
    }

    func autoSendSessionHandoffOutputIfUnedited() async {
        guard state.handoffCountdownRemaining == 0,
              let baseline = state.handoffDraftBaseline,
              state.inputDraft == baseline else {
            return
        }

        let output = state.inputDraft
        cancelSessionHandoffCountdown(clearPendingOutput: true)
        state.failedSessionHandoffMessage = nil
        state.inputDraft = ""
        let retryableMessageCount = state.retryableFailedMessageIDs.count
        do {
            try await sendSessionHandoffOutput(output)
        } catch {
            if state.retryableFailedMessageIDs.count == retryableMessageCount {
                state.inputDraft = output
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
}

private extension ConversationViewModel {
    func canStartSessionHandoff(
        trigger: SessionHandoffTrigger,
        retryingFailedHandoff: Bool
    ) -> Bool {
        let settings = settingsService.current
        guard settings.contextManagementEnabled else {
            return false
        }
        let hasBlockingHandoff = state.isHandingOffSession ||
            state.isAwaitingHandoffSteering ||
            state.pendingHandoffOutput != nil ||
            state.handoffCountdownRemaining != nil ||
            (!retryingFailedHandoff && state.failedSessionHandoffMessage != nil)
        guard !needsSetup else {
            state.lastTurnError = "Complete the first turn before triggering a session handoff."
            return false
        }
        guard !hasBlockingHandoff,
              !state.turnState.isActive,
              !state.isSendingMessage,
              !state.isReconfiguringSession,
              state.pendingToolApproval == nil,
              !hasUnansweredPrompt else {
            if trigger == .manual {
                state.lastTurnError = "Wait for the current conversation action to finish before triggering session handoff."
            }
            return false
        }
        return true
    }

    func makeHiddenSessionHandoffPrompt() -> String {
        SessionHandoffPromptBuilder.hiddenPrompt(
            configuredPrompt: settingsService.current.sessionHandoffPrompt,
            steeringPrompt: state.submittedHandoffSteeringPrompt,
            isSteeringEnabled: settingsService.current.handoffSteeringEnabled
        )
    }

    func makeSessionHandoffOutgoingMessage(output: String) -> String {
        SessionHandoffPromptBuilder.outgoingMessage(
            handoffOutput: output,
            steeringPrompt: state.submittedHandoffSteeringPrompt,
            isSteeringEnabled: settingsService.current.handoffSteeringEnabled
        )
    }

    func handleHiddenSessionHandoffTokens(_ payload: TokenEventPayload) {
        state.clearStreamingText()
        guard !payload.isError, payload.permissionDenials.isEmpty else {
            state.turnState.endTurn()
            failSessionHandoff(payload.stopReason ?? "Session handoff failed.")
            return
        }

        let output = state.hiddenHandoffResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            state.turnState.endTurn()
            failSessionHandoff("Session handoff failed: the hidden handoff prompt returned no context.")
            return
        }

        state.turnState.endTurn()
        Task { @MainActor [self] in
            await finishSessionHandoff(with: output)
        }
    }

    func finishSessionHandoff(with output: String) async {
        do {
            let config = try makeSpawnConfig()
            await flushPendingSaveIfNeeded()
            await prepareForSpawn(config: config)
            try await agentsManager.startFreshSession(conversationId: conversation.id, config: config)
            state.sessionContinuityNotice = nil
            resetSubscriptionTrackingForNewSession()
            subscribe()
            recordContextWindowInvalidation()
            appendSessionHandoffNote()

            if shouldCustomizeSessionHandoffOutput {
                beginSessionHandoffCustomization(output: output)
            } else {
                await sendSessionHandoffOutputImmediately(output)
            }
        } catch {
            failSessionHandoff("Session handoff failed: \(error.localizedDescription)")
        }
    }

    func beginSessionHandoffCustomization(output: String) {
        state.isHandingOffSession = false
        state.hiddenHandoffResponse = ""
        state.pendingHandoffOutput = output
        state.failedSessionHandoffMessage = nil
        state.handoffDraftBaseline = output
        state.inputDraft = output
        startSessionHandoffCountdown()
    }

    func sendSessionHandoffOutputImmediately(_ output: String) async {
        state.isHandingOffSession = false
        state.hiddenHandoffResponse = ""
        state.pendingHandoffOutput = nil
        state.failedSessionHandoffMessage = nil
        state.handoffDraftBaseline = nil
        state.handoffCountdownRemaining = nil
        let retryableMessageCount = state.retryableFailedMessageIDs.count
        do {
            try await sendSessionHandoffOutput(output)
        } catch {
            if state.retryableFailedMessageIDs.count == retryableMessageCount {
                state.inputDraft = output
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
        sessionHandoffCountdownTask = nil
        state.handoffCountdownRemaining = nil
        state.handoffDraftBaseline = nil
        if clearPendingOutput {
            state.pendingHandoffOutput = nil
        }
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
        state.clearStreamingText()
        state.turnState.endTurn()
        state.lastTurnError = message
        if let restorableDraft, state.inputDraft.isEmpty {
            state.inputDraft = restorableDraft
        }
    }

    func clearSubmittedHandoffSteering() {
        state.submittedHandoffSteeringPrompt = nil
        state.sessionHandoffRestorableDraft = nil
    }

    func clearRestorableDraftForEmptyRetryIfNeeded(retryingFailedHandoff: Bool) {
        guard retryingFailedHandoff,
              state.sessionHandoffRestorableDraft != nil,
              state.inputDraft.isEmpty else {
            return
        }

        state.sessionHandoffRestorableDraft = nil
    }

    func preserveVisibleDraftForAutomaticHandoffIfNeeded(
        trigger: SessionHandoffTrigger,
        retryingFailedHandoff: Bool
    ) {
        guard trigger == .automatic,
              !retryingFailedHandoff,
              !state.inputDraft.isEmpty else {
            return
        }

        state.sessionHandoffRestorableDraft = state.inputDraft
    }

    func stashVisibleDraftForHandoffIfNeeded() {
        let hasSubmittedSteeringOrRestorableDraft = state.submittedHandoffSteeringPrompt != nil ||
            state.sessionHandoffRestorableDraft != nil
        guard hasSubmittedSteeringOrRestorableDraft,
              !state.inputDraft.isEmpty else {
            return
        }

        state.sessionHandoffRestorableDraft = state.inputDraft
        state.inputDraft = ""
    }

    func restoreSessionHandoffDraftIfNeeded() {
        guard let restorableDraft = state.sessionHandoffRestorableDraft,
              state.inputDraft.isEmpty else {
            return
        }

        state.inputDraft = restorableDraft
    }

    func appendSessionHandoffNote() {
        guard let dbConversation = dbConversation(),
              let record = ConversationEvent.stop(message: ConversationSessionHandoff.displayMessage)
                .toRecord(conversation: dbConversation) else {
            return
        }

        modelContext.insert(record)
        state.grouper.append(event: record)
        scheduleSave()
    }

    func resetSubscriptionTrackingForNewSession() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        state.lastObservedEventIndex = 0
        state.lastPersistedEventIndex = 0
        state.activeBufferGeneration = nil
        state.activeSubscriptionToken = nil
        state.grouper.resetInFlightStateForNewSession()
    }
}

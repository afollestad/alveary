import AgentCLIKit
import Foundation

extension ConversationViewModel {
    func handleTurnCompleted() {
        state.endTurn()
        scheduleQueueDrainIfNeeded()
    }

    func pauseQueuedMessagesAfterInterruptionIfNeeded() {
        guard state.messageQueue.peekNext() != nil,
              state.currentTurnActivityVisibility == .visible,
              !state.isHandingOffSession,
              state.failedSessionHandoffMessage == nil,
              !state.isGeneratingCommitMessage,
              !state.isDrainingCommitMessageGenerationEvents else {
            return
        }
        state.queuedMessagesPauseReason = .interrupted
    }

    func clearQueuedMessagesPauseIfQueueEmpty() {
        guard state.messageQueue.peekNext() == nil else {
            return
        }
        state.queuedMessagesPauseReason = nil
    }

    func resumeQueuedMessages() {
        state.queuedMessagesPauseReason = nil
        scheduleQueueDrainIfNeeded()
    }

    func sendReserved(
        _ message: String,
        transportText: String? = nil,
        initialGoal: String? = nil,
        attachments: [LocalImageAttachment] = [],
        appShots: [AppShotAttachment] = [],
        providerMetadata: [String: AgentCLIKit.JSONValue] = [:],
        stagedContextOverride: String? = nil,
        useCurrentStagedContextWhenOverrideNil: Bool = true,
        existingLocalUserMessageID: String? = nil,
        marksSessionHandoffSeedTurn: Bool = false
    ) async throws {
        let appliedContext = stagedContextOverride ?? (useCurrentStagedContextWhenOverrideNil ? state.stagedContext : nil)
        let transportMessage = buildTransportMessage(
            message: transportText ?? message,
            stagedContext: appliedContext
        )

        guard let dbConversation = dbConversation() else {
            throw AgentError.spawnFailed("Conversation no longer exists")
        }

        state.lastTurnInterrupted = false
        state.isCancellingTurn = false
        state.activeRuntimeActivityTurnId = nil
        state.pendingSyntheticAssistantDuplicateText = nil
        (state.lastTurnError, state.failedSessionHandoffMessage) = (nil, nil)
        try await sendVisibleAgentMessage(
            transportMessage,
            initialGoal: initialGoal,
            attachments: attachments,
            providerMetadata: providerMetadata
        )
        if useCurrentStagedContextWhenOverrideNil && stagedContextOverride == nil {
            state.stagedContext = nil
        }
        clearConsumedPendingRestoreContext(using: appliedContext)
        markVisibleTurnStarted(isSessionHandoffSeed: marksSessionHandoffSeedTurn)
        state.turnState.beginTurn()
        if let existingLocalUserMessageID {
            state.clearRetryableFailedMessage(id: existingLocalUserMessageID)
        } else {
            insertLocalUserMessage(
                message,
                into: dbConversation,
                imageAttachments: attachments,
                appShots: appShots
            )
        }
    }

    func buildTransportMessage(
        message: String,
        stagedContext: String?
    ) -> String {
        if let context = stagedContext {
            return context + "\n\n" + message
        }
        return message
    }

    func sendVisibleAgentMessage(
        _ message: String,
        initialGoal: String? = nil,
        attachments: [LocalImageAttachment] = [],
        providerMetadata: [String: AgentCLIKit.JSONValue] = [:]
    ) async throws {
        let markedPromptDismissalReplacement = markPromptDismissalNewOutboundTurnStarted()
        do {
            if let initialGoal = initialGoal?.trimmingCharacters(in: .whitespacesAndNewlines),
               !initialGoal.isEmpty {
                try await agentsManager.sendGoalStartMessage(.init(
                    message: message,
                    initialGoal: initialGoal,
                    conversationId: conversation.id,
                    activityVisibility: .visible,
                    attachments: attachments,
                    metadata: providerMetadata
                ))
            } else {
                try await agentsManager.sendMessage(
                    message,
                    conversationId: conversation.id,
                    activityVisibility: .visible,
                    attachments: attachments,
                    metadata: providerMetadata
                )
            }
        } catch {
            restorePromptDismissalNewOutboundTurnStartedIfNeeded(markedPromptDismissalReplacement)
            throw error
        }
    }

    func sendVisibleSteeringMessage(
        _ message: String,
        steeringInputID: String,
        attachments: [LocalImageAttachment] = [],
        providerMetadata: [String: AgentCLIKit.JSONValue] = [:]
    ) async throws {
        let markedPromptDismissalReplacement = markPromptDismissalNewOutboundTurnStarted()
        do {
            try await agentsManager.sendSteeringMessage(
                message,
                conversationId: conversation.id,
                steeringInputID: steeringInputID,
                attachments: attachments,
                metadata: providerMetadata
            )
        } catch {
            restorePromptDismissalNewOutboundTurnStartedIfNeeded(markedPromptDismissalReplacement)
            throw error
        }
    }

    func steerQueuedMessage(id: UUID) async throws {
        guard !state.isNormalSteeringBlockedBySessionHandoff else {
            throw AgentError.spawnFailed("Session handoff is in progress")
        }
        guard providerCanSteerCurrentTurn else {
            throw AgentError.spawnFailed("Wait for the agent to be actively working before steering")
        }
        guard state.inFlightQueuedMessageID == nil else {
            throw AgentError.spawnFailed("Wait for the current queued message action to finish")
        }
        let queuedMessage = try queuedMessageForSteering(id: id)

        var localMessageID: String?
        state.inFlightQueuedMessageID = id
        defer {
            if state.inFlightQueuedMessageID == id {
                state.inFlightQueuedMessageID = nil
            }
        }

        do {
            try await performQueuedSteer(id: id) { localMessageID = $0 }
        } catch {
            if let localMessageID {
                state.markRetryableFailedMessage(
                    id: localMessageID,
                    stagedContext: queuedMessage.stagedContext,
                    transportText: queuedMessage.transportText,
                    attachments: queuedMessage.attachments,
                    appShots: queuedMessage.appShots,
                    providerMetadata: queuedMessage.providerMetadata
                )
            }
            state.lastTurnError = "Steer failed: \(error.localizedDescription)"
            throw error
        }
    }

    func performQueuedSteer(id: UUID, onLocalMessageInserted: (String) -> Void) async throws {
        try await withOutboundReservation {
            guard let queuedMessage = state.messageQueue.remove(id: id),
                  let dbConversation = dbConversation() else {
                throw AgentError.spawnFailed("Conversation no longer exists")
            }
            clearQueuedMessagesPauseIfQueueEmpty()

            let transportMessage = buildTransportMessage(
                message: queuedMessage.transportText ?? queuedMessage.text,
                stagedContext: queuedMessage.stagedContext
            )
            let localMessage = insertLocalUserMessage(
                queuedMessage.text,
                into: dbConversation,
                imageAttachments: queuedMessage.attachments,
                appShots: queuedMessage.appShots
            )
            onLocalMessageInserted(localMessage.id)

            state.lastTurnInterrupted = false
            state.isCancellingTurn = false
            state.lastTurnError = nil
            state.activeRuntimeActivityTurnId = nil
            try await sendVisibleSteeringMessage(
                transportMessage,
                steeringInputID: localMessage.id,
                attachments: queuedMessage.attachments,
                providerMetadata: queuedMessage.providerMetadata
            )
            markVisibleTurnStarted()
            state.turnState.beginTurn()
            clearConsumedPendingRestoreContext(using: queuedMessage.stagedContext)
            state.clearRetryableFailedMessage(id: localMessage.id)
            state.markTranscriptImageAttachments(id: localMessage.id, attachments: queuedMessage.attachments)
            state.markTranscriptAppShots(id: localMessage.id, appShots: queuedMessage.appShots)
            state.respawnAttempts = 0
        }
    }

    func steerNextQueuedMessage() async throws {
        guard let next = state.messageQueue.peekNext() else {
            return
        }
        try await steerQueuedMessage(id: next.id)
    }
}

extension ConversationViewModel {
    func scheduleQueueDrainIfNeeded() {
        scheduleQueueDrainIfNeeded(allowInactiveBeforeFirstActivation: false, allowInitialSetup: false)
    }

    func scheduleExitPlanModeFollowUpDrainIfNeeded() {
        // Denied-plan follow-ups may be staged before the view ever activates, but
        // explicit deactivation must still keep them parked until the view returns.
        scheduleQueueDrainIfNeeded(allowInactiveBeforeFirstActivation: true, allowInitialSetup: true)
    }

    private func scheduleQueueDrainIfNeeded(
        allowInactiveBeforeFirstActivation: Bool,
        allowInitialSetup: Bool
    ) {
        guard queueDrainTask == nil,
              state.messageQueue.peekNext() != nil,
              state.queuedMessagesPauseReason == nil,
              !state.turnState.isActive,
              canDrainForCurrentLifecycle(allowInactiveBeforeFirstActivation: allowInactiveBeforeFirstActivation) else {
            return
        }

        queueDrainTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer { self.queueDrainTask = nil }
            await self.drainNextQueuedMessageIfReady(
                allowInactiveBeforeFirstActivation: allowInactiveBeforeFirstActivation,
                allowInitialSetup: allowInitialSetup
            )
        }
    }
}

private extension ConversationViewModel {
    func drainNextQueuedMessageIfReady(
        allowInactiveBeforeFirstActivation: Bool = false,
        allowInitialSetup: Bool = false
    ) async {
        guard canDrainNextQueuedMessageLocally(
            allowInactiveBeforeFirstActivation: allowInactiveBeforeFirstActivation,
            allowInitialSetup: allowInitialSetup
        ) else {
            return
        }

        let runtimeStatus = await runtimeStatusForQueueDrain()
        guard !Task.isCancelled,
              canDrainNextQueuedMessageLocally(
                  allowInactiveBeforeFirstActivation: allowInactiveBeforeFirstActivation,
                  allowInitialSetup: allowInitialSetup
              ) else {
            return
        }
        guard runtimeStatus == .idle || runtimeStatus == .neutral || runtimeStatus == .stopped else {
            return
        }
        guard let next = state.messageQueue.peekNext(),
              let dbConversation = dbConversation() else {
            return
        }

        state.inFlightQueuedMessageID = next.id
        defer {
            if state.inFlightQueuedMessageID == next.id {
                state.inFlightQueuedMessageID = nil
            }
        }

        do {
            try await sendNextQueuedMessage(next, in: dbConversation)
        } catch {
            state.lastTurnError = "Queued message failed to send: \(error.localizedDescription)"
            state.endTurn()
        }
    }

    func canDrainNextQueuedMessageLocally(
        allowInactiveBeforeFirstActivation: Bool = false,
        allowInitialSetup: Bool = false
    ) -> Bool {
        canDrainForCurrentLifecycle(allowInactiveBeforeFirstActivation: allowInactiveBeforeFirstActivation) &&
            (!needsSetup || allowInitialSetup) &&
            initialSetupTask == nil &&
            state.setupPhase == nil &&
            !state.isCancellingInitialSetup &&
            !state.isSendingMessage &&
            !state.turnState.isActive &&
            state.inFlightQueuedMessageID == nil &&
            state.pendingToolApproval == nil &&
            !hasUnansweredPrompt &&
            state.pendingExitPlanModeFollowUp == nil &&
            !state.hasActiveSessionHandoff &&
            !state.isAutomaticSessionHandoffPending &&
            !state.isCancellingTurn &&
            state.queuedMessagesPauseReason == nil &&
            state.lastTurnError == nil &&
            state.failedSessionHandoffMessage == nil &&
            !state.isReconfiguringSession
    }

    func canDrainForCurrentLifecycle(allowInactiveBeforeFirstActivation: Bool) -> Bool {
        hasActivatedViewLifecycle || (allowInactiveBeforeFirstActivation && !hasEverActivatedViewLifecycle)
    }

    func runtimeStatusForQueueDrain() async -> ActivitySignal {
        let cachedStatus = agentsManager.status(for: conversation.id)
        guard cachedStatus == .busy,
              !state.turnState.isActive,
              state.messageQueue.peekNext() != nil else {
            return cachedStatus
        }
        return await agentsManager.refreshStatus(conversationId: conversation.id)
    }

    func queuedMessageForSteering(id: UUID) throws -> QueuedMessage {
        guard let queuedMessage = state.messageQueue.pending.first(where: { $0.id == id }) else {
            throw AgentError.spawnFailed("That queued message is no longer available")
        }
        guard queuedMessage.requiredPlanModeEnabled == nil else {
            throw AgentError.spawnFailed("Plan-mode queued messages send on the next turn")
        }
        guard queuedMessage.requiredSpeedMode == nil else {
            throw AgentError.spawnFailed("Speed-mode queued messages send on the next turn")
        }
        guard queuedMessage.transportText == nil || queuedMessage.consumedExitPlanModeRevisionGuidance == nil else {
            throw AgentError.spawnFailed("Plan feedback queued messages send on the next turn")
        }
        if !queuedMessage.appShots.isEmpty,
           queuedMessage.providerMetadata[AgentCLIKit.CodexInputMetadata.isAppshot] != .bool(true),
           !hasClaudeAppShotDirectoryGrant(for: queuedMessage.appShots) {
            throw AgentError.spawnFailed("App-shot queued messages send on the next turn until Claude can read the screenshot directory")
        }
        return queuedMessage
    }

    func sendNextQueuedMessage(_ next: QueuedMessage, in dbConversation: Conversation) async throws {
        var localMessageID: String?
        try await prepareQueuedMessageRequirements(next)
        try await withOutboundReservation {
            let sessionRecoveryContext = try await prepareRuntimeForQueuedMessage()
            guard sessionRecoveryContext.shouldContinue else {
                return
            }

            guard let queuedMessage = state.messageQueue.remove(id: next.id) else {
                state.endTurn()
                return
            }
            clearQueuedMessagesPauseIfQueueEmpty()
            let transportText = revisionTransportTextForQueuedMessage(queuedMessage)

            let localMessage = insertLocalUserMessage(
                queuedMessage.text,
                into: dbConversation,
                imageAttachments: queuedMessage.attachments,
                appShots: queuedMessage.appShots
            )
            localMessageID = localMessage.id

            let resolvedStagedContext = resolveSessionRecoveryStagedContext(
                recoveryContext: sessionRecoveryContext.recoveryContext,
                stagedContextOverride: queuedMessage.stagedContext,
                useCurrentStagedContextWhenOverrideNil: false
            )
            do {
                try await deliverPreparedQueuedMessage(
                    queuedMessage,
                    transportText: transportText,
                    stagedContext: resolvedStagedContext.stagedContext,
                    localMessageID: localMessage.id
                )
                state.respawnAttempts = 0
            } catch {
                if let localMessageID {
                    state.markRetryableFailedMessage(
                        id: localMessageID,
                        stagedContext: resolvedStagedContext.stagedContext,
                        transportText: transportText,
                        attachments: queuedMessage.attachments,
                        appShots: queuedMessage.appShots,
                        providerMetadata: queuedMessage.providerMetadata
                    )
                }
                throw error
            }
        }
    }

    func prepareQueuedMessageRequirements(_ queuedMessage: QueuedMessage) async throws {
        let preflightTransportText = revisionTransportTextForQueuedMessage(queuedMessage)
        let requiredPlanModeEnabled = planModeRequirementForQueuedMessage(queuedMessage, transportText: preflightTransportText)

        if let requiredPlanModeEnabled {
            try await ensurePlanModeForOutbound(requiredPlanModeEnabled)
        }
        if let requiredSpeedMode = queuedMessage.requiredSpeedMode {
            try await ensureSpeedModeForOutbound(requiredSpeedMode)
        }
        try await applyPendingSessionSettingsBeforeNextOutboundTurn()
        try await ensureAppShotProviderPrerequisites(appShots: queuedMessage.appShots)
    }

    func deliverPreparedQueuedMessage(
        _ queuedMessage: QueuedMessage,
        transportText: String?,
        stagedContext: String?,
        localMessageID: String
    ) async throws {
        try await deliverMessageReserved(
            queuedMessage.text,
            transportTextOverride: transportText,
            attachments: queuedMessage.attachments,
            appShots: queuedMessage.appShots,
            providerMetadata: queuedMessage.providerMetadata,
            consumedExitPlanModeRevisionGuidance: queuedMessage.consumedExitPlanModeRevisionGuidance,
            stagedContextOverride: stagedContext,
            useCurrentStagedContextWhenOverrideNil: false,
            existingLocalUserMessageID: localMessageID,
            respawnSettingsSource: .currentContinuation
        )
    }

    private func prepareRuntimeForQueuedMessage() async throws -> OutboundRuntimePreparation {
        switch await agentsManager.outboundReadiness(conversationId: conversation.id) {
        case .ready:
            return .proceed(recoveryContext: nil)
        case .respawnRequired:
            guard state.respawnAttempts < Self.maxRespawnAttempts else {
                state.lastTurnError = "Agent process keeps crashing — queued message paused"
                state.respawnAttempts = 0
                state.endTurn()
                return .pause
            }
            state.respawnAttempts += 1
            let recoveryContext = try await respawnRuntimeForOutbound(settingsSource: .currentContinuation)
            return .proceed(recoveryContext: recoveryContext)
        case .blocked(let reason):
            throw AgentError.spawnFailed(reason)
        }
    }

}

private enum OutboundRuntimePreparation {
    case proceed(recoveryContext: String?)
    case pause

    var shouldContinue: Bool {
        guard case .proceed = self else {
            return false
        }
        return true
    }

    var recoveryContext: String? {
        guard case .proceed(let recoveryContext) = self else {
            return nil
        }
        return recoveryContext
    }
}

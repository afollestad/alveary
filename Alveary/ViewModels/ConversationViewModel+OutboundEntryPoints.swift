import Foundation

extension ConversationViewModel {
    func setupAndStart(_ message: String, supportsLocalImageInput: Bool = true) async throws {
        try await applyPendingSessionSettingsBeforeNextOutboundTurn()
        try await withOutboundReservation {
            try await deliverNormalUserMessage(message, supportsLocalImageInput: supportsLocalImageInput)
        }
    }

    func send(
        _ message: String,
        stagedContextOverride: String? = nil,
        supportsLocalImageInput: Bool = true
    ) async throws {
        guard state.messageQueue.peekNext() == nil else {
            throw AgentError.spawnFailed("Resolve the queued message at the head of the queue before sending a new one")
        }

        try await applyPendingSessionSettingsBeforeNextOutboundTurn()
        try await withOutboundReservation {
            try await deliverNormalUserMessage(
                message,
                stagedContextOverride: stagedContextOverride,
                supportsLocalImageInput: supportsLocalImageInput
            )
        }
    }

    func queueOrSend(
        _ message: String,
        requiredPlanModeEnabled: Bool? = nil,
        requiredSpeedMode: AgentSpeedMode? = nil,
        supportsLocalImageInput: Bool = true
    ) async throws {
        try validateQueueOrSendAvailability()
        let outbound = outboundText(
            for: message,
            requiredPlanModeEnabled: requiredPlanModeEnabled,
            requiredSpeedMode: requiredSpeedMode,
            supportsLocalImageInput: supportsLocalImageInput
        )

        guard !shouldQueueOutboundMessage else {
            enqueueOutboundMessage(
                outbound,
                requiredPlanModeEnabled: requiredPlanModeEnabled,
                requiredSpeedMode: requiredSpeedMode
            )
            return
        }

        if needsSetup {
            try await runInitialSetupOutbound(
                outbound,
                requiredPlanModeEnabled: requiredPlanModeEnabled,
                requiredSpeedMode: requiredSpeedMode
            )
        } else {
            try await sendOutboundNow(
                outbound,
                requiredPlanModeEnabled: requiredPlanModeEnabled,
                requiredSpeedMode: requiredSpeedMode
            )
        }
    }

    func retryFailedUserMessage(id: String) async throws {
        guard !isAgentActivelyWorking, !state.isSendingMessage else {
            throw AgentError.spawnFailed("Wait for the current turn/send to finish before retrying the message")
        }
        guard state.retryableFailedMessageIDs.contains(id) else {
            return
        }
        guard let message = retryableVisibleMessage(id: id) else {
            state.clearRetryableFailedMessage(id: id)
            return
        }

        do {
            try await applyPendingSessionSettingsBeforeNextOutboundTurn()
            try await withOutboundReservation {
                try await deliverMessageReserved(
                    message,
                    transportTextOverride: state.retryableFailedMessageTransportTexts[id],
                    attachments: state.retryableFailedMessageAttachments[id] ?? [],
                    stagedContextOverride: state.retryableFailedMessageStagedContexts[id],
                    existingLocalUserMessageID: id
                )
            }
        } catch {
            state.lastTurnError = "Retry failed: \(error.localizedDescription)"
            throw error
        }
    }
}

private extension ConversationViewModel {
    var shouldQueueOutboundMessage: Bool {
        isAgentActivelyWorking || state.isSendingMessage || state.messageQueue.peekNext() != nil
    }

    func validateQueueOrSendAvailability() throws {
        guard !state.hasActiveSessionHandoff else {
            throw AgentError.spawnFailed("Session handoff is in progress")
        }
        guard !state.isAwaitingExitPlanModeFollowUp else {
            throw AgentError.spawnFailed("Wait for the plan response to be sent before sending another message")
        }
    }

    func outboundText(
        for message: String,
        requiredPlanModeEnabled: Bool?,
        requiredSpeedMode: AgentSpeedMode?,
        supportsLocalImageInput: Bool
    ) -> OutboundMessageText {
        let base: OutboundMessageText
        if requiredPlanModeEnabled != nil || requiredSpeedMode != nil {
            base = OutboundMessageText(visibleText: message)
        } else {
            base = preparedNormalUserOutboundText(message)
        }
        return base.resolvingImageAttachments(
            state.stagedImageAttachments,
            supportsLocalImageInput: supportsLocalImageInput,
            fallbackText: fallbackText(visibleText:attachments:)
        )
    }

    func deliverNormalUserMessage(
        _ message: String,
        stagedContextOverride: String? = nil,
        supportsLocalImageInput: Bool = true
    ) async throws {
        let outbound = preparedNormalUserOutboundText(message).resolvingImageAttachments(
            state.stagedImageAttachments,
            supportsLocalImageInput: supportsLocalImageInput,
            fallbackText: fallbackText(visibleText:attachments:)
        )
        try await deliverMessageReserved(
            outbound.visibleText,
            transportTextOverride: outbound.transportText,
            attachments: outbound.attachments,
            consumedAttachments: outbound.consumedAttachments,
            consumedExitPlanModeRevisionGuidance: outbound.consumedExitPlanModeRevisionGuidance,
            stagedContextOverride: stagedContextOverride
        )
    }

    func enqueueOutboundMessage(
        _ outbound: OutboundMessageText,
        requiredPlanModeEnabled: Bool?,
        requiredSpeedMode: AgentSpeedMode?
    ) {
        state.messageQueue.enqueue(
            outbound.visibleText,
            stagedContext: state.stagedContext,
            requiredPlanModeEnabled: queuedPlanModeRequirement(outbound, fallback: requiredPlanModeEnabled),
            requiredSpeedMode: requiredSpeedMode,
            transportText: outbound.transportText,
            attachments: outbound.attachments,
            consumedExitPlanModeRevisionGuidance: outbound.consumedExitPlanModeRevisionGuidance
        )
        state.stagedContext = nil
        clearStagedImageAttachmentsIfTheyMatch(outbound.consumedAttachments)
        scheduleQueueDrainIfNeeded()
    }

    func sendOutboundNow(
        _ outbound: OutboundMessageText,
        requiredPlanModeEnabled: Bool?,
        requiredSpeedMode: AgentSpeedMode?
    ) async throws {
        do {
            try await ensureOutboundModes(
                requiredPlanModeEnabled: requiredPlanModeEnabled,
                requiredSpeedMode: requiredSpeedMode
            )
            try await applyPendingSessionSettingsBeforeNextOutboundTurn()
        } catch {
            restoreExitPlanModeRevisionGuidanceIfNeeded(outbound.consumedExitPlanModeRevisionGuidance)
            throw error
        }
        try await withOutboundReservation {
            try await deliverMessageReserved(
                outbound.visibleText,
                transportTextOverride: outbound.transportText,
                attachments: outbound.attachments,
                consumedAttachments: outbound.consumedAttachments,
                consumedExitPlanModeRevisionGuidance: outbound.consumedExitPlanModeRevisionGuidance
            )
        }
    }

    func runInitialSetupOutbound(
        _ outbound: OutboundMessageText,
        requiredPlanModeEnabled: Bool?,
        requiredSpeedMode: AgentSpeedMode?
    ) async throws {
        // Initial setup predates the visible turn, so keep it cancellable through `cancel()`.
        let task = Task { [self] in
            try await sendOutboundNow(
                outbound,
                requiredPlanModeEnabled: requiredPlanModeEnabled,
                requiredSpeedMode: requiredSpeedMode
            )
        }
        initialSetupTask = task
        defer { initialSetupTask = nil }
        try await task.value
    }

    func ensureOutboundModes(
        requiredPlanModeEnabled: Bool?,
        requiredSpeedMode: AgentSpeedMode?
    ) async throws {
        if let requiredPlanModeEnabled {
            try await ensurePlanModeForOutbound(requiredPlanModeEnabled)
        }
        if let requiredSpeedMode {
            try await ensureSpeedModeForOutbound(requiredSpeedMode)
        }
    }

    func queuedPlanModeRequirement(
        _ outbound: OutboundMessageText,
        fallback: Bool?
    ) -> Bool? {
        outbound.transportText == nil ? fallback : true
    }

    func retryableVisibleMessage(id: String) -> String? {
        guard let record = userMessageRecord(id: id),
              let message = record.content else {
            return nil
        }
        let hasRetryableAttachments = !(state.retryableFailedMessageAttachments[id]?.isEmpty ?? true)
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasRetryableAttachments else {
            return nil
        }
        return message
    }
}

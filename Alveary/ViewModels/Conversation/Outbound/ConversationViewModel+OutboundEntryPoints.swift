import Foundation

extension ConversationViewModel {
    func setupAndStart(_ message: String, supportsLocalImageInput: Bool = true) async throws {
        try ensureOrdinaryScheduledOutboundAvailable()
        try await applyPendingSessionSettingsBeforeNextOutboundTurn()
        try await ensureAppShotProviderPrerequisites(appShots: state.stagedAppShots)
        try await withOrdinaryOutboundReservation {
            try await deliverNormalUserMessage(message, supportsLocalImageInput: supportsLocalImageInput)
        }
    }

    func send(
        _ message: String,
        stagedContextOverride: String? = nil,
        supportsLocalImageInput: Bool = true
    ) async throws {
        try ensureOrdinaryScheduledOutboundAvailable()
        guard state.messageQueue.peekNext() == nil else {
            throw AgentError.spawnFailed("Resolve the queued message at the head of the queue before sending a new one")
        }

        try await applyPendingSessionSettingsBeforeNextOutboundTurn()
        try await ensureAppShotProviderPrerequisites(appShots: state.stagedAppShots)
        try await withOrdinaryOutboundReservation {
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
        let outbound = try outboundText(
            for: message,
            requiredPlanModeEnabled: requiredPlanModeEnabled,
            requiredSpeedMode: requiredSpeedMode,
            supportsLocalImageInput: supportsLocalImageInput
        )

        guard !shouldQueueOutboundMessage,
              !defersOrdinaryScheduledOutbound else {
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

    /// Delivers a prompt another thread's agent sent through `send_prompt_to_thread`, taking the
    /// same queue-or-send decision as `queueOrSend`, and reports which it took.
    ///
    /// Deliberately bypasses `outboundText(for:)`: this conversation's staged attachments, app
    /// shots, and pending plan-revision guidance belong to whatever its own user is composing here
    /// and must not ride out on a message that arrived from elsewhere. Restore context still
    /// applies through the shared helpers — it precedes the next message whoever sends it.
    func queueOrSendRelayedPrompt(_ outbound: OutboundMessageText) async throws -> RelayedPromptDelivery {
        try validateQueueOrSendAvailability()
        guard !shouldQueueOutboundMessage,
              !defersOrdinaryScheduledOutbound else {
            enqueueOutboundMessage(outbound, requiredPlanModeEnabled: nil, requiredSpeedMode: nil)
            return .queued
        }
        if needsSetup {
            try await runInitialSetupOutbound(outbound, requiredPlanModeEnabled: nil, requiredSpeedMode: nil)
        } else {
            try await sendOutboundNow(outbound, requiredPlanModeEnabled: nil, requiredSpeedMode: nil)
        }
        return .sent
    }

    func sendBeforePausedQueuedMessages(
        _ message: String,
        supportsLocalImageInput: Bool = true
    ) async throws {
        guard state.queuedMessagesPauseReason != nil,
              state.messageQueue.peekNext() != nil else {
            try await queueOrSend(message, supportsLocalImageInput: supportsLocalImageInput)
            return
        }

        try validateQueueOrSendAvailability()
        try ensureCanSendBeforePausedQueuedMessages()
        let outbound = try outboundText(
            for: message,
            requiredPlanModeEnabled: nil,
            requiredSpeedMode: nil,
            supportsLocalImageInput: supportsLocalImageInput
        )
        if needsSetup {
            try await runInitialSetupBeforePausedQueueOutbound(outbound)
        } else {
            try await sendBeforePausedQueueNow(outbound)
        }
    }

    func retryFailedUserMessage(id: String) async throws {
        try ensureOrdinaryScheduledOutboundAvailable()
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
            let appShots = state.retryableFailedMessageAppShots[id] ?? []
            let fileAttachments = state.retryableFailedMessageFileAttachments[id] ?? []
            try await ensureAppShotProviderPrerequisites(appShots: appShots)
            try await withOrdinaryOutboundReservation {
                try await deliverMessageReserved(
                    message,
                    transportTextOverride: state.retryableFailedMessageTransportTexts[id],
                    attachments: state.retryableFailedMessageAttachments[id] ?? [],
                    appShots: appShots,
                    providerMetadata: state.retryableFailedMessageProviderMetadata[id] ?? [:],
                    consumedFileAttachments: fileAttachments,
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

/// Which way `queueOrSendRelayedPrompt` went: the prompt started a turn, or is waiting behind one.
enum RelayedPromptDelivery: Equatable, Sendable {
    case sent
    case queued
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
    ) throws -> OutboundMessageText {
        let base: OutboundMessageText
        if requiredPlanModeEnabled != nil || requiredSpeedMode != nil {
            base = OutboundMessageText(visibleText: message)
        } else {
            base = preparedNormalUserOutboundText(message)
        }
        return try base.resolvingImageAttachments(
            state.stagedImageAttachments,
            supportsLocalImageInput: supportsLocalImageInput,
            fallbackText: fallbackText(visibleText:attachments:)
        ).resolvingFileAttachments(
            state.stagedFileAttachments,
            fallbackText: fallbackText(visibleText:fileAttachments:)
        ).resolvingAppShots(
            state.stagedAppShots,
            providerID: conversation.provider ?? settingsService.current.defaultProvider
        )
    }

    func deliverNormalUserMessage(
        _ message: String,
        stagedContextOverride: String? = nil,
        supportsLocalImageInput: Bool = true
    ) async throws {
        let outbound = try preparedNormalUserOutboundText(message).resolvingImageAttachments(
            state.stagedImageAttachments,
            supportsLocalImageInput: supportsLocalImageInput,
            fallbackText: fallbackText(visibleText:attachments:)
        ).resolvingFileAttachments(
            state.stagedFileAttachments,
            fallbackText: fallbackText(visibleText:fileAttachments:)
        ).resolvingAppShots(
            state.stagedAppShots,
            providerID: conversation.provider ?? settingsService.current.defaultProvider
        )
        try await deliverMessageReserved(
            outbound.visibleText,
            transportTextOverride: outbound.transportText,
            attachments: outbound.attachments,
            appShots: outbound.appShots,
            providerMetadata: outbound.providerMetadata,
            consumedAttachments: outbound.consumedAttachments,
            consumedFileAttachments: outbound.consumedFileAttachments,
            consumedAppShots: outbound.consumedAppShots,
            consumedExitPlanModeRevisionGuidance: outbound.consumedExitPlanModeRevisionGuidance,
            stagedContextOverride: stagedContextOverride,
            relayedFrom: outbound.relayedFrom
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
            fileAttachments: outbound.consumedFileAttachments,
            appShots: outbound.appShots,
            providerMetadata: outbound.providerMetadata,
            consumedExitPlanModeRevisionGuidance: outbound.consumedExitPlanModeRevisionGuidance,
            relayedFrom: outbound.relayedFrom
        )
        state.stagedContext = nil
        clearStagedImageAttachmentsIfTheyMatch(outbound.consumedAttachments)
        clearStagedFileAttachmentsIfTheyMatch(outbound.consumedFileAttachments)
        clearStagedAppShotsIfTheyMatch(outbound.consumedAppShots)
        scheduleQueueDrainIfNeeded()
    }

    func sendOutboundNow(
        _ outbound: OutboundMessageText,
        requiredPlanModeEnabled: Bool?,
        requiredSpeedMode: AgentSpeedMode?
    ) async throws {
        try ensureOrdinaryScheduledOutboundAvailable()
        do {
            try await ensureOutboundModes(
                requiredPlanModeEnabled: requiredPlanModeEnabled,
                requiredSpeedMode: requiredSpeedMode
            )
            try await applyPendingSessionSettingsBeforeNextOutboundTurn()
            try await ensureAppShotProviderPrerequisites(appShots: outbound.appShots)
        } catch {
            restoreExitPlanModeRevisionGuidanceIfNeeded(outbound.consumedExitPlanModeRevisionGuidance)
            throw error
        }
        try await withOrdinaryOutboundReservation {
            try await deliverMessageReserved(
                outbound.visibleText,
                transportTextOverride: outbound.transportText,
                attachments: outbound.attachments,
                appShots: outbound.appShots,
                providerMetadata: outbound.providerMetadata,
                consumedAttachments: outbound.consumedAttachments,
                consumedFileAttachments: outbound.consumedFileAttachments,
                consumedAppShots: outbound.consumedAppShots,
                consumedExitPlanModeRevisionGuidance: outbound.consumedExitPlanModeRevisionGuidance,
                relayedFrom: outbound.relayedFrom
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

    func runInitialSetupBeforePausedQueueOutbound(_ outbound: OutboundMessageText) async throws {
        // Initial setup predates the visible turn, so keep it cancellable through `cancel()`.
        let task = Task { [self] in
            try await sendBeforePausedQueueNow(outbound)
        }
        initialSetupTask = task
        defer { initialSetupTask = nil }
        try await task.value
    }

    func sendBeforePausedQueueNow(_ outbound: OutboundMessageText) async throws {
        try ensureOrdinaryScheduledOutboundAvailable()
        do {
            try await ensureOutboundModes(
                requiredPlanModeEnabled: nil,
                requiredSpeedMode: nil
            )
            try await applyPendingSessionSettingsBeforeNextOutboundTurn()
            try await ensureAppShotProviderPrerequisites(appShots: outbound.appShots)
            try ensureCanSendBeforePausedQueuedMessages()
        } catch {
            restoreExitPlanModeRevisionGuidanceIfNeeded(outbound.consumedExitPlanModeRevisionGuidance)
            throw error
        }
        try await withOrdinaryOutboundReservation {
            state.queuedMessagesPauseReason = nil
            state.pausedQueueSendConfirmation = nil
            try await deliverMessageReserved(
                outbound.visibleText,
                transportTextOverride: outbound.transportText,
                attachments: outbound.attachments,
                appShots: outbound.appShots,
                providerMetadata: outbound.providerMetadata,
                consumedAttachments: outbound.consumedAttachments,
                consumedFileAttachments: outbound.consumedFileAttachments,
                consumedAppShots: outbound.consumedAppShots,
                consumedExitPlanModeRevisionGuidance: outbound.consumedExitPlanModeRevisionGuidance,
                relayedFrom: outbound.relayedFrom
            )
        }
    }

    func ensureCanSendBeforePausedQueuedMessages() throws {
        guard !isAgentActivelyWorking, !state.isSendingMessage else {
            throw AgentError.spawnFailed("Wait for the current turn/send to finish before sending another message")
        }
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
        outbound.consumedExitPlanModeRevisionGuidance == nil ? fallback : true
    }

    func retryableVisibleMessage(id: String) -> String? {
        guard let record = userMessageRecord(id: id),
              let message = record.content else {
            return nil
        }
        let hasRetryableAttachments = !(state.retryableFailedMessageAttachments[id]?.isEmpty ?? true)
        let hasRetryableFileAttachments = !(state.retryableFailedMessageFileAttachments[id]?.isEmpty ?? true)
        let hasRetryableAppShots = !(state.retryableFailedMessageAppShots[id]?.isEmpty ?? true)
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            hasRetryableAttachments ||
            hasRetryableFileAttachments ||
            hasRetryableAppShots else {
            return nil
        }
        return message
    }
}

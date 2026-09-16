import AgentCLIKit
import Foundation

extension ConversationViewModel {
    func sendVisibleSteeringMessage(
        _ message: String,
        steeringInputID: String,
        attachments: [LocalImageAttachment] = [],
        harnessMetadata: [String: AgentCLIKit.JSONValue] = [:]
    ) async throws {
        guard declaredHarnessFeatures.supportsMidTurnSteering else {
            throw AgentError.spawnFailed("This harness does not support steering.")
        }
        try await validateOutboundCapabilities(attachments: attachments, usingLiveSettings: true)
        let markedPromptDismissalReplacement = markPromptDismissalNewOutboundTurnStarted()
        if capabilityHarnessID == "opencode" { markVisibleTurnStarted() }
        do {
            try await agentsManager.sendSteeringMessage(
                message,
                conversationId: conversation.id,
                steeringInputID: steeringInputID,
                attachments: attachments,
                metadata: harnessMetadata
            )
        } catch {
            restorePromptDismissalNewOutboundTurnStartedIfNeeded(markedPromptDismissalReplacement)
            throw error
        }
    }

    func steer(_ message: String, supportsLocalImageInput: Bool = true) async throws {
        try await validateStagedOptionalFeatures(supportsLocalImageInput: supportsLocalImageInput, usingLiveSettings: true)
        try ensureOrdinaryScheduledOutboundAvailable()
        guard !state.isNormalSteeringBlockedBySessionHandoff else {
            throw AgentError.spawnFailed("Session handoff is in progress")
        }
        guard harnessCanSteerCurrentTurn else {
            throw AgentError.spawnFailed("Wait for the agent to be actively working before steering")
        }

        let outbound = try OutboundMessageText(visibleText: message).resolvingImageAttachments(
            state.stagedImageAttachments,
            supportsLocalImageInput: supportsLocalImageInput,
            fallbackText: fallbackText(visibleText:attachments:)
        ).resolvingFileAttachments(
            state.stagedFileAttachments,
            fallbackText: fallbackText(visibleText:fileAttachments:)
        ).resolvingAppShots(
            state.stagedAppShots,
            harnessID: capabilityHarnessID
        )
        try await ensureAppShotHarnessPrerequisites(appShots: outbound.appShots)

        try await withOrdinaryOutboundReservation {
            guard let dbConversation = dbConversation() else {
                throw AgentError.spawnFailed("Conversation no longer exists")
            }
            try await performVisibleSteeringAttempt(outbound, in: dbConversation)
        }
    }
}

private extension ConversationViewModel {
    func performVisibleSteeringAttempt(
        _ outbound: OutboundMessageText,
        in dbConversation: Conversation
    ) async throws {
        let localMessage = prepareVisibleSteeringAttempt(outbound, in: dbConversation)
        do {
            try await sendVisibleSteeringMessage(
                outbound.transportText ?? outbound.visibleText,
                steeringInputID: localMessage.id,
                attachments: outbound.attachments,
                harnessMetadata: outbound.harnessMetadata
            )
            if capabilityHarnessID != "opencode" {
                markVisibleTurnStarted()
                state.turnState.beginTurn()
            }
            state.clearRetryableFailedMessage(id: localMessage.id)
            state.markTranscriptImageAttachments(id: localMessage.id, attachments: outbound.attachments)
            state.markTranscriptFileAttachments(id: localMessage.id, attachments: outbound.consumedFileAttachments)
            state.markTranscriptAppShots(id: localMessage.id, appShots: outbound.appShots)
        } catch {
            state.markRetryableFailedMessage(
                id: localMessage.id,
                stagedContext: nil,
                transportText: outbound.transportText,
                attachments: outbound.attachments,
                fileAttachments: outbound.consumedFileAttachments,
                appShots: outbound.appShots,
                harnessMetadata: outbound.harnessMetadata
            )
            state.lastTurnError = "Steer failed: \(error.localizedDescription)"
            throw error
        }
    }

    func prepareVisibleSteeringAttempt(
        _ outbound: OutboundMessageText,
        in dbConversation: Conversation
    ) -> ConversationEventRecord {
        let localMessage = insertLocalUserMessage(
            outbound.visibleText,
            into: dbConversation,
            imageAttachments: outbound.attachments,
            fileAttachments: outbound.consumedFileAttachments,
            appShots: outbound.appShots,
            relayedFrom: outbound.relayedFrom
        )
        clearStagedImageAttachmentsIfTheyMatch(outbound.consumedAttachments)
        clearStagedFileAttachmentsIfTheyMatch(outbound.consumedFileAttachments)
        clearStagedAppShotsIfTheyMatch(outbound.consumedAppShots)
        state.lastTurnInterrupted = false
        state.isCancellingTurn = false
        state.lastTurnError = nil
        state.activeRuntimeActivityTurnId = nil
        return localMessage
    }
}

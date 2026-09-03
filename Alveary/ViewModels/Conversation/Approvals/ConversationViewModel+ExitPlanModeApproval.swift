import AgentCLIKit
import Foundation

/// Approve/deny entry points for the `ExitPlanMode` confirmation plus the transient revision
/// guidance for plain denials. The staged custom-follow-up lifecycle lives in
/// `ConversationViewModel+ExitPlanModeFollowUp.swift`.
extension ConversationViewModel {
    func approveExitPlanMode(toolUseId: String) async throws {
        // A throwing `makeSpawnConfig` (no conversation or working directory) falls through to the
        // ordinary path, which builds its own config and surfaces the same error — the staged change
        // stays staged either way, so nothing is silently dropped.
        guard let pending = state.pendingSessionSettingsChange,
              pending.hasModelChange || pending.hasEffortChange,
              let restartConfig = try? exitPlanModeRestartConfig(pending) else {
            try await resolveExitPlanModeToolUseApproval(toolUseId: toolUseId, decision: .allow)
            return
        }

        // Implementation is new work rather than a continuation of the planning turn, so it is the one
        // deferred approval allowed to consume staged model/effort. Applying them means replacing the
        // Claude process, which takes seconds; without this the composer would offer a Stop button
        // mid-restart instead of the reconfiguring state.
        state.isReconfiguringSession = true
        defer { state.isReconfiguringSession = false }

        try await resolveExitPlanModeToolUseApproval(
            toolUseId: toolUseId,
            decision: .allow,
            providerRestartConfig: restartConfig
        )
        finishPendingSessionSettingsApply(pending: pending, config: restartConfig)
    }

    /// Keeps every continuation setting — permission mode, speed, host-tool exposure, workspace
    /// authorization — and overrides only what the user changed at the plan prompt.
    private func exitPlanModeRestartConfig(_ pending: PendingSessionSettingsChange) throws -> AgentSpawnConfig {
        try makeSpawnConfig(settingsSource: .currentContinuation)
            .withModel(
                pending.pending.model,
                effort: AppSettings.normalizedEffortLevel(pending.pending.effort)
            )
    }

    func denyExitPlanMode(toolUseId: String, followUp: String? = nil) async throws {
        let trimmedFollowUp = followUp?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let approval = state.pendingToolApproval?.request.toolUseId == toolUseId
            ? state.pendingToolApproval?.request
            : nil
        let providerSnapshot = exitPlanModeRevisionProviderSnapshot()
        if let trimmedFollowUp,
           let approval {
            stagePendingExitPlanModeFollowUp(
                message: Self.exitPlanModeRevisionFollowUpPrompt(feedback: trimmedFollowUp),
                approval: approval,
                providerSnapshot: providerSnapshot
            )
        }

        do {
            try await resolveExitPlanModeToolUseApproval(toolUseId: toolUseId, decision: .deny)
            if trimmedFollowUp == nil,
               let approval {
                stagePendingExitPlanModeRevisionGuidance(
                    approval: approval,
                    providerSnapshot: providerSnapshot
                )
            }
            finishDeniedExitPlanModeApproval(toolUseId: toolUseId)
        } catch {
            clearPendingExitPlanModeFollowUpIfNeeded(toolUseId: toolUseId)
            clearPendingExitPlanModeRevisionGuidanceIfNeeded(toolUseId: toolUseId)
            throw error
        }
    }

    nonisolated static func exitPlanModeRevisionFollowUpPrompt(feedback: String) -> String {
        feedback
    }

    func clearPendingExitPlanModeRevisionGuidanceIfNeeded(toolUseId: String) {
        guard state.pendingExitPlanModeRevisionGuidance?.toolUseId == toolUseId else {
            return
        }
        state.pendingExitPlanModeRevisionGuidance = nil
    }

    func clearPendingExitPlanModeRevisionGuidance() {
        state.pendingExitPlanModeRevisionGuidance = nil
    }

    func clearPendingExitPlanModeDenialState() {
        clearPendingExitPlanModeFollowUp()
        clearPendingExitPlanModeRevisionGuidance()
        state.messageQueue.clearExitPlanModeRevisionGuidance()
    }

    func preparedNormalUserOutboundText(_ visibleText: String) -> OutboundMessageText {
        guard let guidance = state.pendingExitPlanModeRevisionGuidance else {
            return OutboundMessageText(visibleText: visibleText)
        }
        guard canUseExitPlanModeRevisionGuidance(guidance) else {
            state.pendingExitPlanModeRevisionGuidance = nil
            return OutboundMessageText(visibleText: visibleText)
        }

        state.pendingExitPlanModeRevisionGuidance = nil
        return OutboundMessageText(
            visibleText: visibleText,
            transportText: ExitPlanModeDenialPolicy.revisionTransportText(visibleText: visibleText),
            consumedExitPlanModeRevisionGuidance: guidance
        )
    }

    func restoreExitPlanModeRevisionGuidanceIfNeeded(_ guidance: PendingExitPlanModeRevisionGuidance?) {
        guard let guidance,
              state.pendingExitPlanModeRevisionGuidance == nil,
              canUseExitPlanModeRevisionGuidance(guidance) else {
            return
        }
        state.pendingExitPlanModeRevisionGuidance = guidance
    }

    /// The provider-facing text a drained queued message sends. Plan-revision guidance is the one
    /// transport text that can go stale — plan mode may have ended while the message waited — so
    /// it is dropped once it no longer applies. Any other transport text — an app shot's hidden
    /// context, a relayed prompt's sender header — is exactly what the message was queued with,
    /// and dropping it would silently send the visible text instead.
    func transportTextForQueuedMessage(_ queuedMessage: QueuedMessage) -> String? {
        guard let transportText = queuedMessage.transportText else {
            return nil
        }
        guard let guidance = queuedMessage.consumedExitPlanModeRevisionGuidance else {
            return transportText
        }
        return canUseExitPlanModeRevisionGuidance(guidance) ? transportText : nil
    }

    func planModeRequirementForQueuedMessage(
        _ queuedMessage: QueuedMessage,
        transportText: String?
    ) -> Bool? {
        if queuedMessage.transportText != nil, transportText == nil {
            return nil
        }
        return queuedMessage.requiredPlanModeEnabled
    }

    func finishDeniedExitPlanModeApproval(toolUseId: String) {
        if let pendingApproval = state.pendingToolApproval,
           pendingApproval.request.toolName == "ExitPlanMode",
           pendingApproval.request.toolUseId == toolUseId,
           resolvedStatus(for: pendingApproval.status) == .denied {
            persistResolvedToolApproval(pendingApproval, refreshTranscript: false)
            state.pendingToolApproval = nil
            refreshTranscriptForToolApprovalStatusChanges()
        }

        // Denying or dismissing plan exit is terminal for this confirmation UI.
        // The provider may still emit trailing denial tokens, but the composer
        // should return to its normal surface immediately.
        state.activeRuntimeActivityTurnId = nil
        state.isAutomaticSessionHandoffPending = false
        state.isCancellingTurn = false
        state.lastTurnError = nil
        state.clearStreamingText()
        state.endTurn()
        recordLocalVisibleTurnEndedIfNeeded()

        schedulePendingExitPlanModeFollowUpQuietFallbackIfNeeded()
        schedulePendingExitPlanModeFollowUpWatchdogIfNeeded()
    }

    private func stagePendingExitPlanModeRevisionGuidance(
        approval: ToolApprovalRequest,
        providerSnapshot: ExitPlanModeRevisionProviderSnapshot
    ) {
        guard ExitPlanModeDenialPolicy.requiresRevisionTransportGuidance(providerId: providerSnapshot.providerId) else {
            state.pendingExitPlanModeRevisionGuidance = nil
            return
        }
        state.pendingExitPlanModeRevisionGuidance = PendingExitPlanModeRevisionGuidance(
            toolUseId: approval.toolUseId,
            sessionId: approval.sessionId,
            providerId: providerSnapshot.providerId,
            providerSessionId: providerSnapshot.providerSessionId
        )
    }

    private func canUseExitPlanModeRevisionGuidance(_ guidance: PendingExitPlanModeRevisionGuidance) -> Bool {
        guard effectivePlanModeEnabled,
              ExitPlanModeDenialPolicy.requiresRevisionTransportGuidance(providerId: guidance.providerId) else {
            return false
        }
        let providerSnapshot = exitPlanModeRevisionProviderSnapshot()
        guard providerSnapshot.providerId == guidance.providerId else {
            return false
        }
        if let expectedSessionId = guidance.providerSessionId,
           let currentSessionId = providerSnapshot.providerSessionId,
           currentSessionId != expectedSessionId {
            return false
        }
        return true
    }

    func exitPlanModeRevisionProviderSnapshot() -> ExitPlanModeRevisionProviderSnapshot {
        let dbConversation = dbConversation()
        let providerId = state.liveSessionConfig?.providerId
            ?? dbConversation?.provider
            ?? settingsService.current.defaultProvider
        let providerSessionId: String?
        if dbConversation?.providerSessionProviderId == providerId {
            providerSessionId = dbConversation?.providerSessionId
        } else {
            providerSessionId = nil
        }
        return ExitPlanModeRevisionProviderSnapshot(
            providerId: providerId,
            providerSessionId: providerSessionId
        )
    }
}

struct ExitPlanModeRevisionProviderSnapshot {
    let providerId: String
    let providerSessionId: String?
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

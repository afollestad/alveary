import Foundation

private let exitPlanModeFollowUpQuietDelay: Duration = .milliseconds(750)

extension ConversationViewModel {
    func approveExitPlanMode(toolUseId: String) async throws {
        try await resolveExitPlanModeToolUseApproval(toolUseId: toolUseId, decision: .allow)
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

    @discardableResult
    func enqueuePendingExitPlanModeFollowUpIfReady(clearedToolUseId: String) -> Bool {
        guard state.pendingToolApproval == nil,
              let followUp = state.pendingExitPlanModeFollowUp,
              followUp.toolUseId == clearedToolUseId,
              followUp.phase == .readyToSend else {
            return false
        }
        guard canSendPendingExitPlanModeFollowUp(followUp) else {
            clearPendingExitPlanModeFollowUp()
            return false
        }

        cancelPendingExitPlanModeFollowUpQuietTask()
        let planModeStillEnabled = effectivePlanModeEnabled
        let transportText = planModeStillEnabled ? followUp.transportText : nil
        let consumedRevisionGuidance = transportText == nil ? nil : PendingExitPlanModeRevisionGuidance(
            toolUseId: followUp.toolUseId,
            sessionId: followUp.sessionId,
            providerId: followUp.providerId,
            providerSessionId: followUp.providerSessionId
        )
        state.pendingExitPlanModeFollowUp = nil
        state.messageQueue.prepend(
            followUp.message,
            stagedContext: nil,
            requiredPlanModeEnabled: planModeStillEnabled ? true : nil,
            transportText: transportText,
            consumedExitPlanModeRevisionGuidance: consumedRevisionGuidance
        )
        scheduleExitPlanModeFollowUpDrainIfNeeded()
        return true
    }

    nonisolated static func exitPlanModeRevisionFollowUpPrompt(feedback: String) -> String {
        feedback
    }

    func clearPendingExitPlanModeFollowUpIfNeeded(toolUseId: String) {
        guard state.pendingExitPlanModeFollowUp?.toolUseId == toolUseId else {
            return
        }
        clearPendingExitPlanModeFollowUp()
    }

    func clearPendingExitPlanModeFollowUp() {
        cancelPendingExitPlanModeFollowUpQuietTask()
        state.pendingExitPlanModeFollowUp = nil
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

    func revisionTransportTextForQueuedMessage(_ queuedMessage: QueuedMessage) -> String? {
        guard let transportText = queuedMessage.transportText,
              let guidance = queuedMessage.consumedExitPlanModeRevisionGuidance,
              canUseExitPlanModeRevisionGuidance(guidance) else {
            return nil
        }
        return transportText
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
    }

    func markPendingExitPlanModeFollowUpReadyAfterTerminalBoundary(
        toolUseId: String,
        sessionId: String? = nil,
        turnId: String? = nil,
        subscriptionToken: UUID? = nil
    ) -> Bool {
        guard state.pendingToolApproval == nil,
              var followUp = state.pendingExitPlanModeFollowUp,
              followUp.toolUseId == toolUseId,
              sessionId == nil || followUp.sessionId == sessionId,
              turnId == nil || followUp.sourceTurnId == nil || followUp.sourceTurnId == turnId,
              subscriptionToken == nil ||
                  followUp.sourceSubscriptionToken == nil ||
                  followUp.sourceSubscriptionToken == subscriptionToken else {
            return false
        }

        followUp.phase = .readyToSend
        state.pendingExitPlanModeFollowUp = followUp
        return enqueuePendingExitPlanModeFollowUpIfReady(clearedToolUseId: toolUseId)
    }

    func markPendingExitPlanModeFollowUpReadyAfterTerminalToken(_ payload: TokenEventPayload) -> Bool {
        guard let followUp = state.pendingExitPlanModeFollowUp,
              followUp.phase == .awaitingDeniedExitTurn,
              payload.completesTurn,
              terminalTokenMatchesPendingExitPlanModeFollowUp(payload, followUp: followUp) else {
            return false
        }

        return markPendingExitPlanModeFollowUpReadyAfterTerminalBoundary(
            toolUseId: followUp.toolUseId,
            sessionId: followUp.sessionId,
            subscriptionToken: followUp.sourceSubscriptionToken
        )
    }

    func markPendingExitPlanModeFollowUpReadyAfterRuntimeIdle(
        turnId: String?,
        outcome: ConversationRuntimeActivityOutcome
    ) -> Bool {
        guard let followUp = state.pendingExitPlanModeFollowUp,
              followUp.phase == .awaitingDeniedExitTurn,
              followUp.sourceTurnId != nil,
              followUp.sourceTurnId == turnId,
              outcome.isTerminalForExitPlanModeFollowUp else {
            return false
        }

        return markPendingExitPlanModeFollowUpReadyAfterTerminalBoundary(
            toolUseId: followUp.toolUseId,
            sessionId: followUp.sessionId,
            turnId: turnId
        )
    }

    func recordPendingExitPlanModeFollowUpEventIfNeeded(subscriptionToken: UUID? = nil) {
        guard var followUp = state.pendingExitPlanModeFollowUp,
              followUp.phase == .awaitingDeniedExitTurn,
              subscriptionToken == nil ||
                  followUp.sourceSubscriptionToken == nil ||
                  followUp.sourceSubscriptionToken == subscriptionToken else {
            return
        }

        followUp.lastObservedEventIndex = state.lastObservedEventIndex
        state.pendingExitPlanModeFollowUp = followUp
        cancelPendingExitPlanModeFollowUpQuietTask()
    }

    func drainPendingExitPlanModeFollowUpAfterSubscriptionFinish(token: UUID) -> Bool {
        guard let followUp = state.pendingExitPlanModeFollowUp,
              followUp.phase == .awaitingDeniedExitTurn,
              followUp.sourceSubscriptionToken == token else {
            return false
        }

        return markPendingExitPlanModeFollowUpReadyAfterTerminalBoundary(
            toolUseId: followUp.toolUseId,
            sessionId: followUp.sessionId,
            subscriptionToken: token
        )
    }

    func cancelPendingExitPlanModeFollowUpQuietTask() {
        state.pendingExitPlanModeFollowUpQuietTask?.cancel()
        state.pendingExitPlanModeFollowUpQuietTask = nil
    }

    func cancelPendingExitPlanModeFollowUpQuietTaskForViewDeactivation() {
        cancelPendingExitPlanModeFollowUpQuietTask()
    }

    func schedulePendingExitPlanModeFollowUpQuietFallbackIfNeeded() {
        guard let followUp = state.pendingExitPlanModeFollowUp,
              followUp.phase == .awaitingDeniedExitTurn else {
            return
        }

        cancelPendingExitPlanModeFollowUpQuietTask()
        let toolUseId = followUp.toolUseId
        let sessionId = followUp.sessionId
        let sourceSubscriptionToken = followUp.sourceSubscriptionToken
        let sourceEventIndex = followUp.sourceEventIndex
        let lastObservedEventIndex = followUp.lastObservedEventIndex
        state.pendingExitPlanModeFollowUpQuietTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: exitPlanModeFollowUpQuietDelay)
            guard let self,
                  !Task.isCancelled,
                  let currentFollowUp = self.state.pendingExitPlanModeFollowUp,
                  currentFollowUp.phase == .awaitingDeniedExitTurn,
                  currentFollowUp.toolUseId == toolUseId,
                  currentFollowUp.sessionId == sessionId,
                  currentFollowUp.sourceEventIndex == sourceEventIndex,
                  currentFollowUp.lastObservedEventIndex == lastObservedEventIndex,
                  self.state.lastObservedEventIndex == sourceEventIndex,
                  sourceSubscriptionToken == nil ||
                      currentFollowUp.sourceSubscriptionToken == self.state.activeSubscriptionToken else {
                return
            }

            if self.markPendingExitPlanModeFollowUpReadyAfterTerminalBoundary(
                toolUseId: toolUseId,
                sessionId: sessionId,
                subscriptionToken: sourceSubscriptionToken
            ) {
                self.handleTurnCompleted()
            }
        }
    }

    private func stagePendingExitPlanModeFollowUp(
        message: String,
        approval: ToolApprovalRequest,
        providerSnapshot: ExitPlanModeRevisionProviderSnapshot
    ) {
        cancelPendingExitPlanModeFollowUpQuietTask()
        let shouldWrapTransport = effectivePlanModeEnabled &&
            ExitPlanModeDenialPolicy.requiresRevisionTransportGuidance(providerId: providerSnapshot.providerId)
        let transportText = shouldWrapTransport
            ? ExitPlanModeDenialPolicy.revisionTransportText(visibleText: message)
            : nil
        state.pendingExitPlanModeFollowUp = PendingExitPlanModeFollowUp(
            toolUseId: approval.toolUseId,
            sessionId: approval.sessionId,
            providerId: providerSnapshot.providerId,
            providerSessionId: providerSnapshot.providerSessionId,
            message: message,
            transportText: transportText,
            sourceTurnId: state.activeRuntimeActivityTurnId,
            sourceSubscriptionToken: state.activeSubscriptionToken,
            sourceBufferGeneration: state.activeBufferGeneration,
            sourceEventIndex: state.lastObservedEventIndex,
            lastObservedEventIndex: state.lastObservedEventIndex,
            phase: .awaitingDeniedExitTurn
        )
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

    private func canSendPendingExitPlanModeFollowUp(_ followUp: PendingExitPlanModeFollowUp) -> Bool {
        let providerSnapshot = exitPlanModeRevisionProviderSnapshot()
        guard providerSnapshot.providerId == followUp.providerId else {
            return false
        }
        if let expectedSessionId = followUp.providerSessionId,
           let currentSessionId = providerSnapshot.providerSessionId,
           currentSessionId != expectedSessionId {
            return false
        }
        return true
    }

    private func exitPlanModeRevisionProviderSnapshot() -> ExitPlanModeRevisionProviderSnapshot {
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

    private func terminalTokenMatchesPendingExitPlanModeFollowUp(
        _ payload: TokenEventPayload,
        followUp: PendingExitPlanModeFollowUp
    ) -> Bool {
        if let sourceSubscriptionToken = followUp.sourceSubscriptionToken,
           sourceSubscriptionToken != state.activeSubscriptionToken {
            return false
        }
        guard !payload.permissionDenials.isEmpty else {
            return true
        }
        return payload.permissionDenials.contains { denial in
            denial.toolUseId == followUp.toolUseId ||
                (denial.toolUseId == nil && denial.toolName == "ExitPlanMode")
        }
    }
}

struct OutboundMessageText: Equatable, Sendable {
    let visibleText: String
    let transportText: String?
    let consumedExitPlanModeRevisionGuidance: PendingExitPlanModeRevisionGuidance?

    init(
        visibleText: String,
        transportText: String? = nil,
        consumedExitPlanModeRevisionGuidance: PendingExitPlanModeRevisionGuidance? = nil
    ) {
        self.visibleText = visibleText
        self.transportText = transportText
        self.consumedExitPlanModeRevisionGuidance = consumedExitPlanModeRevisionGuidance
    }
}

private struct ExitPlanModeRevisionProviderSnapshot {
    let providerId: String
    let providerSessionId: String?
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension ConversationRuntimeActivityOutcome {
    var isTerminalForExitPlanModeFollowUp: Bool {
        switch self {
        case .completed, .failed, .interrupted:
            return true
        case .unknown:
            return false
        }
    }
}

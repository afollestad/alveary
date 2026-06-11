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
        if let trimmedFollowUp,
           let approval = state.pendingToolApproval?.request,
           approval.toolUseId == toolUseId {
            stagePendingExitPlanModeFollowUp(message: trimmedFollowUp, approval: approval)
        }

        do {
            try await resolveExitPlanModeToolUseApproval(toolUseId: toolUseId, decision: .deny)
            finishDeniedExitPlanModeApproval(toolUseId: toolUseId)
        } catch {
            clearPendingExitPlanModeFollowUpIfNeeded(toolUseId: toolUseId)
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

        cancelPendingExitPlanModeFollowUpQuietTask()
        state.pendingExitPlanModeFollowUp = nil
        state.messageQueue.prepend(followUp.message, stagedContext: nil)
        scheduleExitPlanModeFollowUpDrainIfNeeded()
        return true
    }

    func clearPendingExitPlanModeFollowUpIfNeeded(toolUseId: String) {
        guard state.pendingExitPlanModeFollowUp?.toolUseId == toolUseId else {
            return
        }
        cancelPendingExitPlanModeFollowUpQuietTask()
        state.pendingExitPlanModeFollowUp = nil
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
        state.turnState.endTurn()

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

    private func stagePendingExitPlanModeFollowUp(message: String, approval: ToolApprovalRequest) {
        cancelPendingExitPlanModeFollowUpQuietTask()
        state.pendingExitPlanModeFollowUp = PendingExitPlanModeFollowUp(
            toolUseId: approval.toolUseId,
            sessionId: approval.sessionId,
            message: message,
            sourceTurnId: state.activeRuntimeActivityTurnId,
            sourceSubscriptionToken: state.activeSubscriptionToken,
            sourceBufferGeneration: state.activeBufferGeneration,
            sourceEventIndex: state.lastObservedEventIndex,
            lastObservedEventIndex: state.lastObservedEventIndex,
            phase: .awaitingDeniedExitTurn
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

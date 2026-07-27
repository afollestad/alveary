import AgentCLIKit
import Foundation

private let exitPlanModeFollowUpQuietDelay: Duration = .milliseconds(750)

/// Lifecycle for the denied-plan custom follow-up: staging, drain triggers, the quiet fallback, and
/// the no-activity watchdog. The approve/deny entry points live in
/// `ConversationViewModel+ExitPlanModeApproval.swift`.
extension ConversationViewModel {
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
        cancelPendingExitPlanModeFollowUpWatchdogTask()
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

    func clearPendingExitPlanModeFollowUpIfNeeded(toolUseId: String) {
        guard state.pendingExitPlanModeFollowUp?.toolUseId == toolUseId else {
            return
        }
        clearPendingExitPlanModeFollowUp()
    }

    func clearPendingExitPlanModeFollowUp() {
        cancelPendingExitPlanModeFollowUpQuietTask()
        cancelPendingExitPlanModeFollowUpWatchdogTask()
        state.pendingExitPlanModeFollowUp = nil
    }

    /// A fallback deferred resolution resets subscription tracking and resubscribes, which mints a new
    /// subscription token and zeroes the observed-event cursor. Rebind the staged follow-up to those
    /// new identities: keeping the pre-resume values leaves every drain guard keyed to a dead token, so
    /// the follow-up could never send and the composer would stay busy forever.
    func rebindPendingExitPlanModeFollowUpAfterSubscriptionReset(toolUseId: String) {
        guard let followUp = state.pendingExitPlanModeFollowUp,
              followUp.toolUseId == toolUseId,
              followUp.phase == .awaitingDeniedExitTurn else {
            return
        }

        state.pendingExitPlanModeFollowUp = PendingExitPlanModeFollowUp(
            toolUseId: followUp.toolUseId,
            sessionId: followUp.sessionId,
            providerId: followUp.providerId,
            providerSessionId: followUp.providerSessionId,
            message: followUp.message,
            transportText: followUp.transportText,
            sourceTurnId: state.activeRuntimeActivityTurnId,
            sourceSubscriptionToken: state.activeSubscriptionToken,
            sourceBufferGeneration: state.activeBufferGeneration,
            sourceEventIndex: state.lastObservedEventIndex,
            lastObservedEventIndex: state.lastObservedEventIndex,
            phase: .awaitingDeniedExitTurn
        )
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

    func cancelPendingExitPlanModeFollowUpTasksForViewDeactivation() {
        cancelPendingExitPlanModeFollowUpQuietTask()
        cancelPendingExitPlanModeFollowUpWatchdogTask()
    }

    func cancelPendingExitPlanModeFollowUpWatchdogTask() {
        state.pendingExitPlanModeFollowUpWatchdogTask?.cancel()
        state.pendingExitPlanModeFollowUpWatchdogTask = nil
    }

    /// Last-resort recovery for a follow-up whose drain guards can never be satisfied — for example a
    /// stale subscription token from before an app restart. Unlike the quiet fallback, the watchdog
    /// ignores identity guards: after a full window with no stream activity at all, it force-drains the
    /// follow-up rather than leaving the composer pinned busy forever.
    func schedulePendingExitPlanModeFollowUpWatchdogIfNeeded() {
        guard let followUp = state.pendingExitPlanModeFollowUp,
              followUp.phase == .awaitingDeniedExitTurn else {
            return
        }

        cancelPendingExitPlanModeFollowUpWatchdogTask()
        let toolUseId = followUp.toolUseId
        let observedEventIndex = state.lastObservedEventIndex
        let delay = exitPlanModeFollowUpWatchdogDelay
        state.pendingExitPlanModeFollowUpWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self,
                  !Task.isCancelled,
                  let currentFollowUp = self.state.pendingExitPlanModeFollowUp,
                  currentFollowUp.phase == .awaitingDeniedExitTurn,
                  currentFollowUp.toolUseId == toolUseId else {
                return
            }
            guard self.state.lastObservedEventIndex == observedEventIndex else {
                // Stream activity arrived during the window; give the real drain paths another window.
                self.schedulePendingExitPlanModeFollowUpWatchdogIfNeeded()
                return
            }

            if self.forcePendingExitPlanModeFollowUpReady(toolUseId: toolUseId) {
                self.handleTurnCompleted()
            } else if self.state.pendingExitPlanModeFollowUp != nil {
                // A pending approval owns the composer right now; retry after another quiet window.
                self.schedulePendingExitPlanModeFollowUpWatchdogIfNeeded()
            }
        }
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

    func stagePendingExitPlanModeFollowUp(
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

    private func forcePendingExitPlanModeFollowUpReady(toolUseId: String) -> Bool {
        guard state.pendingToolApproval == nil,
              var followUp = state.pendingExitPlanModeFollowUp,
              followUp.toolUseId == toolUseId,
              followUp.phase == .awaitingDeniedExitTurn else {
            return false
        }

        followUp.phase = .readyToSend
        state.pendingExitPlanModeFollowUp = followUp
        return enqueuePendingExitPlanModeFollowUpIfReady(clearedToolUseId: toolUseId)
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

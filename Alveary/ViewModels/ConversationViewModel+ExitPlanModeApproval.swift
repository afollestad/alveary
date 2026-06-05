import Foundation

extension ConversationViewModel {
    func approveExitPlanMode(toolUseId: String) async throws {
        try await resolveExitPlanModeToolUseApproval(toolUseId: toolUseId, decision: .allow)
    }

    func denyExitPlanMode(toolUseId: String, followUp: String? = nil) async throws {
        let trimmedFollowUp = followUp?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        if let trimmedFollowUp {
            state.pendingExitPlanModeFollowUp = PendingExitPlanModeFollowUp(
                toolUseId: toolUseId,
                message: trimmedFollowUp
            )
        }

        do {
            try await resolveExitPlanModeToolUseApproval(toolUseId: toolUseId, decision: .deny)
            if finishDeniedExitPlanModeApproval(toolUseId: toolUseId, shouldDrainFollowUp: trimmedFollowUp != nil) {
                handleTurnCompleted()
            }
        } catch {
            clearPendingExitPlanModeFollowUpIfNeeded(toolUseId: toolUseId)
            throw error
        }
    }

    @discardableResult
    func enqueuePendingExitPlanModeFollowUpIfReady(clearedToolUseId: String) -> Bool {
        guard state.pendingToolApproval == nil,
              let followUp = state.pendingExitPlanModeFollowUp,
              followUp.toolUseId == clearedToolUseId else {
            return false
        }

        state.pendingExitPlanModeFollowUp = nil
        state.messageQueue.prepend(followUp.message, stagedContext: nil)
        return true
    }

    func clearPendingExitPlanModeFollowUpIfNeeded(toolUseId: String) {
        guard state.pendingExitPlanModeFollowUp?.toolUseId == toolUseId else {
            return
        }
        state.pendingExitPlanModeFollowUp = nil
    }

    @discardableResult
    func finishDeniedExitPlanModeApproval(toolUseId: String, shouldDrainFollowUp: Bool) -> Bool {
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

        guard shouldDrainFollowUp else {
            return false
        }
        return enqueuePendingExitPlanModeFollowUpIfReady(clearedToolUseId: toolUseId)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

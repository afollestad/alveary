import Foundation

extension ConversationViewModel {
    func ensureCanReserveOutbound() throws {
        guard !state.isReconfiguringSession else {
            throw AgentError.spawnFailed("Session changes are still being applied")
        }
        guard !state.hasActiveSessionHandoff else {
            throw AgentError.spawnFailed("Session handoff is in progress")
        }
        guard !hasUnansweredPrompt else {
            throw AgentError.spawnFailed("Answer the pending question before sending another message")
        }
        guard state.pendingToolApproval == nil else {
            throw AgentError.spawnFailed("Approve or deny the pending tool use before sending another message")
        }
        guard !state.isAwaitingExitPlanModeFollowUp else {
            throw AgentError.spawnFailed("Wait for the plan response to be sent before sending another message")
        }
        guard !state.isSendingMessage else {
            throw AgentError.spawnFailed("Another message is already being sent")
        }
    }

    func withOutboundReservation<T>(_ body: () async throws -> T) async throws -> T {
        try ensureCanReserveOutbound()
        let keepAwakeSource = KeepAwakeActivitySource.outboundConversationWork(conversationId: conversation.id)
        activeKeepAwakeSource = keepAwakeSource
        keepAwakeService.setActive(true, for: keepAwakeSource)
        state.isSendingMessage = true
        defer {
            state.isSendingMessage = false
            keepAwakeService.setActive(false, for: keepAwakeSource)
            if activeKeepAwakeSource == keepAwakeSource {
                activeKeepAwakeSource = nil
            }
        }
        return try await body()
    }
}

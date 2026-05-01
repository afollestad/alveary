import Foundation

struct ToolApprovalLiveResolutionResult {
    let additionalApprovals: [ToolApprovalRequest]
    let sessionApprovalEffective: Bool
}

extension ConversationViewModel {
    func resolveAgentToolApproval(
        _ pendingApproval: PendingToolApproval,
        decision: ClaudeToolApprovalDecision,
        updatedToolInput: String?,
        sessionApproval: AgentSessionApprovalGrant?,
        config: AgentSpawnConfig
    ) async throws -> ToolApprovalLiveResolutionResult {
        let additionalApprovals = relatedDeferredToolApprovals(for: pendingApproval.request)
        let sessionApprovalEffective = try await agentsManager.resolveToolApproval(
            AgentToolApprovalResolutionRequest(
                conversationId: conversation.id,
                approval: pendingApproval.request,
                resolution: ClaudeToolApprovalResolution(
                    decision: decision,
                    updatedInput: updatedToolInput
                ),
                additionalApprovals: additionalApprovals,
                sessionApproval: sessionApproval,
                config: config
            )
        )
        return ToolApprovalLiveResolutionResult(
            additionalApprovals: additionalApprovals,
            sessionApprovalEffective: sessionApprovalEffective
        )
    }

    func finishLiveDeniedToolApprovalIfNeeded(
        isResolvingLiveHookApproval: Bool,
        decision: ClaudeToolApprovalDecision
    ) {
        guard isResolvingLiveHookApproval, decision == .deny else {
            return
        }

        // Claude should emit a terminal permission-denial result after the hook
        // returns, but the UI must not stay locked in an active turn if that
        // trailing token is delayed or dropped.
        state.turnState.endTurn()
        state.clearStreamingText()
        state.isAutomaticSessionHandoffPending = false
    }
}

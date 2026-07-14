import AgentCLIKit
import Foundation

extension ConversationViewModel {
    func resolveToolUseApproval(
        toolUseId: String,
        sessionId: String? = nil,
        decision: ClaudeToolApprovalDecision,
        sessionApprovalScope: ToolApprovalSessionScope? = nil,
        responseText: String? = nil
    ) async throws {
        guard !hasUnansweredPrompt else {
            throw AgentError.spawnFailed("Answer the pending question before resolving tool approval")
        }
        guard var pendingApproval = pendingToolApprovalForResolution(toolUseId: toolUseId, sessionId: sessionId) else {
            return
        }
        guard pendingApproval.status == .pending else {
            return
        }
        guard !state.isSendingMessage else {
            throw AgentError.spawnFailed("Wait for the current approval to finish before resolving tool approval")
        }

        pendingApproval.status = approvalStatus(
            for: decision,
            sessionApprovalScope: sessionApprovalScope
        )
        state.pendingToolApproval = pendingApproval
        state.isSendingMessage = true
        defer { state.isSendingMessage = false }

        do {
            try await resumeDeferredToolUse(
                pendingApproval,
                decision: decision,
                sessionApprovalScope: sessionApprovalScope,
                updatedToolInput: nil,
                responseText: responseText
            )
        } catch {
            state.pendingToolApproval = PendingToolApproval(request: pendingApproval.request, status: .pending)
            clearPendingExitPlanModeFollowUpIfNeeded(toolUseId: pendingApproval.request.toolUseId)
            clearPendingExitPlanModeRevisionGuidanceIfNeeded(toolUseId: pendingApproval.request.toolUseId)
            state.lastTurnError = "Tool approval failed: \(error.localizedDescription)"
            throw error
        }
    }

    func pendingToolApprovalForResolution(toolUseId: String, sessionId: String?) -> PendingToolApproval? {
        if let pendingApproval = state.pendingToolApproval,
           pendingApproval.request.toolUseId == toolUseId,
           sessionId == nil || pendingApproval.request.sessionId == sessionId {
            return pendingApproval
        }
        guard let approval = unresolvedToolApproval(toolUseId: toolUseId, sessionId: sessionId) else {
            return nil
        }
        return PendingToolApproval(request: approval, status: .pending)
    }

    func resumeDeferredToolUse(
        _ pendingApproval: PendingToolApproval,
        decision: ClaudeToolApprovalDecision,
        sessionApprovalScope: ToolApprovalSessionScope?,
        updatedToolInput: String?,
        responseText: String? = nil
    ) async throws {
        let isResolvingLiveHookApproval = await isResolvingLiveHookApproval(pendingApproval)
        let config = try makeSpawnConfig(settingsSource: .currentContinuation)
        let sessionApproval = sessionApprovalScope.flatMap {
            pendingApproval.request.sessionApprovalGrant(
                conversationId: conversation.id,
                providerId: config.providerId,
                scope: $0
            )
        }
        try await prepareForApprovalResumeIfNeeded(
            isResolvingLiveHookApproval: isResolvingLiveHookApproval,
            config: config
        )
        let liveResolution = try await resolveAgentToolApproval(
            pendingApproval,
            resolution: ClaudeToolApprovalResolution(
                decision: decision,
                updatedInput: updatedToolInput,
                responseText: responseText
            ),
            sessionApproval: sessionApproval,
            config: config
        )
        finishApprovalResolution(
            pendingApproval,
            decision: decision,
            sessionApprovalScope: sessionApprovalScope,
            liveResolution: liveResolution,
            isResolvingLiveHookApproval: isResolvingLiveHookApproval
        )
    }

    func updateResolvedToolApprovalState(
        _ pendingApproval: PendingToolApproval,
        additionalApprovals: [ToolApprovalRequest],
        relatedApprovalStatus: ToolApprovalStatus
    ) {
        guard pendingApproval.request.toolName != "ExitPlanMode" else {
            persistResolvedToolApproval(pendingApproval, refreshTranscript: false)
            persistRelatedToolApprovalStatuses(additionalApprovals, pendingStatus: relatedApprovalStatus)
            return
        }

        persistResolvedToolApproval(pendingApproval, refreshTranscript: false)
        persistRelatedToolApprovalStatuses(additionalApprovals, pendingStatus: relatedApprovalStatus)
        state.pendingToolApproval = nil
        hydratePendingToolApprovalIfNeeded()
        refreshTranscriptForToolApprovalStatusChanges()
    }

    func persistRelatedToolApprovalStatuses(
        _ approvals: [ToolApprovalRequest],
        pendingStatus: ToolApprovalStatus
    ) {
        guard let relatedStatus = resolvedStatus(for: pendingStatus) else {
            return
        }
        for approval in approvals {
            persistToolApprovalStatus(
                relatedStatus,
                toolUseId: approval.toolUseId,
                sessionId: approval.sessionId,
                refreshTranscript: false
            )
        }
    }

    func approvalStatus(
        for decision: ClaudeToolApprovalDecision,
        sessionApprovalScope: ToolApprovalSessionScope?
    ) -> ToolApprovalStatus {
        switch (decision, sessionApprovalScope) {
        case (.allow, .exact):
            return .approvingForSessionExact
        case (.allow, .group):
            return .approvingForSessionGroup
        case (.allow, nil):
            return .approving
        case (.deny, _):
            return .denying
        }
    }

    func resetSubscriptionTrackingForToolApprovalResume() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        state.lastObservedEventIndex = 0
        state.lastPersistedEventIndex = 0
        state.activeBufferGeneration = nil
        state.activeSubscriptionToken = nil
        state.activeRuntimeActivityTurnId = nil
    }

    func toolApprovalProviderId() -> String {
        conversation.provider ?? settingsService.current.defaultProvider
    }

    func shouldResolveInactiveLiveToolApproval(_ pendingApproval: PendingToolApproval) -> Bool {
        // `tool_deferred` ends Alveary's local turn while Codex may still be paused on this
        // interaction. Keep the decision live so approving or denying the plan does not reset the
        // replay cursor and resubscribe to the already-rendered plan turn.
        pendingApproval.request.toolName == "ExitPlanMode"
    }
}

private extension ConversationViewModel {
    func isResolvingLiveHookApproval(_ pendingApproval: PendingToolApproval) async -> Bool {
        let hasActiveTurn = state.turnState.isActive
        let hasRunningAgent = await agentsManager.isRunning(conversationId: conversation.id)
        return hasRunningAgent && (hasActiveTurn || shouldResolveInactiveLiveToolApproval(pendingApproval))
    }

    func prepareForApprovalResumeIfNeeded(
        isResolvingLiveHookApproval: Bool,
        config: AgentSpawnConfig
    ) async throws {
        if !isResolvingLiveHookApproval {
            try await prepareForSpawn(config: config)
        }
        await flushPendingSaveIfNeeded()
        if !isResolvingLiveHookApproval {
            resetSubscriptionTrackingForToolApprovalResume()
        }
    }

    func finishApprovalResolution(
        _ pendingApproval: PendingToolApproval,
        decision: ClaudeToolApprovalDecision,
        sessionApprovalScope: ToolApprovalSessionScope?,
        liveResolution: ToolApprovalLiveResolutionResult,
        isResolvingLiveHookApproval: Bool
    ) {
        let resolved = relatedApprovalResolutionStatus(
            pendingApproval,
            decision: decision,
            sessionApprovalScope: sessionApprovalScope,
            liveResolution: liveResolution
        )
        updateResolvedToolApprovalState(
            resolved.pendingApproval,
            additionalApprovals: liveResolution.additionalApprovals,
            relatedApprovalStatus: resolved.relatedStatus
        )
        finishLiveDeniedToolApprovalIfNeeded(
            isResolvingLiveHookApproval: isResolvingLiveHookApproval,
            decision: decision
        )
        state.lastTurnError = nil
        if !isResolvingLiveHookApproval {
            subscribe()
        }
    }

    func relatedApprovalResolutionStatus(
        _ pendingApproval: PendingToolApproval,
        decision: ClaudeToolApprovalDecision,
        sessionApprovalScope: ToolApprovalSessionScope?,
        liveResolution: ToolApprovalLiveResolutionResult
    ) -> (pendingApproval: PendingToolApproval, relatedStatus: ToolApprovalStatus) {
        guard decision == .allow,
              sessionApprovalScope != nil,
              !liveResolution.sessionApprovalEffective else {
            return (pendingApproval, pendingApproval.status)
        }
        return (
            PendingToolApproval(request: pendingApproval.request, status: .approving),
            .approving
        )
    }
}

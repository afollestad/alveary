import Foundation
import SwiftData

extension ConversationViewModel {
    func hydratePendingToolApprovalIfNeeded() {
        guard state.pendingToolApproval == nil,
              let approval = latestUnresolvedToolApproval() else {
            return
        }

        if let resolvedStatus = resolvedToolApprovalStatusFromClaudeSession(approval) {
            persistToolApprovalStatus(
                resolvedStatus,
                toolUseId: approval.toolUseId,
                sessionId: approval.sessionId
            )
            return
        }

        state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
    }

    func approveToolUse(toolUseId: String) async throws {
        try await resolveToolUseApproval(toolUseId: toolUseId, decision: .allow)
    }

    func approveToolUseForSession(toolUseId: String, scope: ToolApprovalSessionScope) async throws {
        try await resolveToolUseApproval(
            toolUseId: toolUseId,
            decision: .allow,
            sessionApprovalScope: scope
        )
    }

    func denyToolUse(toolUseId: String) async throws {
        try await resolveToolUseApproval(toolUseId: toolUseId, decision: .deny)
    }

    func toolApprovalSelection(for approval: ToolApprovalRequest) async -> ToolApprovalSelection? {
        let providerId = toolApprovalProviderId()
        return await agentsManager.toolApprovalSelection(
            providerId: providerId,
            conversationId: conversation.id,
            sessionId: approval.sessionId
        )
    }

    func recordToolApprovalSelection(_ selection: ToolApprovalSelection, for approval: ToolApprovalRequest) {
        let providerId = toolApprovalProviderId()
        let conversationId = conversation.id
        let sessionId = approval.sessionId
        Task {
            await agentsManager.recordToolApprovalSelection(
                selection,
                providerId: providerId,
                conversationId: conversationId,
                sessionId: sessionId
            )
        }
    }
}

extension ConversationViewModel {
    func handleToolDeferredTokenIfNeeded(_ payload: TokenEventPayload) -> Bool {
        guard payload.stopReason == "tool_deferred" else {
            return false
        }

        state.isCancellingTurn = false
        state.lastTurnInterrupted = false
        state.lastTurnError = nil
        state.turnState.endTurn()
        return true
    }

    func handleToolApprovalRequested(_ approval: ToolApprovalRequest) -> Bool {
        guard state.pendingToolApproval?.request != approval else {
            return false
        }
        // A completed tool result is terminal for that approval; do not reopen stale provider prompts.
        guard !toolApprovalAlreadyHasResult(approval) else {
            return false
        }

        replacePendingToolApproval(with: approval)
        return true
    }

    func handleToolApprovalFailed(_ failure: ToolApprovalFailure) -> Bool {
        state.lastTurnError = failure.message
        let didSupersedeRecord = supersedeFailedToolApprovalRecord(failure)
        guard let pendingApproval = state.pendingToolApproval,
              toolApprovalFailure(failure, matches: pendingApproval.request) else {
            if didSupersedeRecord {
                refreshTranscriptForToolApprovalStatusChanges()
            }
            return true
        }

        state.pendingToolApproval = nil
        refreshTranscriptForToolApprovalStatusChanges()
        return true
    }

    func clearResolvedPendingToolApprovalIfNeeded() {
        guard let pendingApproval = state.pendingToolApproval,
              pendingApproval.status != .pending else {
            return
        }

        restorePermissionModeAfterPlanExitIfNeeded(pendingApproval)
        persistResolvedToolApproval(pendingApproval)
        state.pendingToolApproval = nil
    }

    func replacePendingToolApproval(with approval: ToolApprovalRequest) {
        if state.pendingToolApproval?.request == approval {
            return
        }

        if let pendingApproval = state.pendingToolApproval,
           let resolvedStatus = resolvedStatus(for: pendingApproval.status) {
            persistToolApprovalStatus(
                resolvedStatus,
                toolUseId: pendingApproval.request.toolUseId,
                sessionId: pendingApproval.request.sessionId,
                refreshTranscript: false
            )
        }

        if !shouldPreservePendingToolApprovalBatch(replacingWith: approval) {
            supersedeUnresolvedToolApprovalRecords(refreshTranscript: false)
        }
        refreshTranscriptForToolApprovalStatusChanges()
        state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
    }

    func supersedePendingToolApprovalAfterPromptAnswer(_ pendingApproval: PendingToolApproval?) {
        guard let pendingApproval,
              pendingApproval.status == .pending,
              state.pendingToolApproval?.request.toolUseId == pendingApproval.request.toolUseId else {
            return
        }

        persistToolApprovalStatus(
            .superseded,
            toolUseId: pendingApproval.request.toolUseId,
            sessionId: pendingApproval.request.sessionId,
            refreshTranscript: false
        )
        state.pendingToolApproval = nil
        refreshTranscriptForToolApprovalStatusChanges()
    }

    func answerDeferredAskUserQuestion(
        _ pendingApproval: PendingToolApproval,
        answers: [(question: String, answer: String)]
    ) async throws {
        guard let updatedToolInput = pendingApproval.request.askUserQuestionUpdatedInput(answers: answers) else {
            throw AgentError.spawnFailed("Question prompt can no longer be answered")
        }

        let resolvingApproval = PendingToolApproval(
            request: pendingApproval.request,
            status: .approving
        )
        state.pendingToolApproval = resolvingApproval

        do {
            try await resumeDeferredToolUse(
                resolvingApproval,
                decision: .allow,
                sessionApprovalScope: nil,
                updatedToolInput: updatedToolInput
            )
        } catch {
            state.pendingToolApproval = PendingToolApproval(request: pendingApproval.request, status: .pending)
            state.lastTurnError = "Prompt answer failed: \(error.localizedDescription)"
            throw error
        }
    }

    func clearResolvedToolApprovalFromClaudeSessionIfNeeded(
        _ approval: ToolApprovalRequest,
        refreshTranscript: Bool = false
    ) -> ToolApprovalStatus? {
        guard let resolvedStatus = resolvedToolApprovalStatusFromClaudeSession(approval) else {
            return nil
        }

        persistToolApprovalStatus(
            resolvedStatus,
            toolUseId: approval.toolUseId,
            sessionId: approval.sessionId,
            refreshTranscript: refreshTranscript
        )
        state.pendingToolApproval = nil
        return resolvedStatus
    }
}

private extension ConversationViewModel {
    func resolveToolUseApproval(
        toolUseId: String,
        decision: ClaudeToolApprovalDecision,
        sessionApprovalScope: ToolApprovalSessionScope? = nil
    ) async throws {
        guard !hasUnansweredPrompt else {
            throw AgentError.spawnFailed("Answer the pending question before resolving tool approval")
        }
        guard var pendingApproval = state.pendingToolApproval,
              pendingApproval.request.toolUseId == toolUseId else {
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
                updatedToolInput: nil
            )
        } catch {
            state.pendingToolApproval = PendingToolApproval(request: pendingApproval.request, status: .pending)
            state.lastTurnError = "Tool approval failed: \(error.localizedDescription)"
            throw error
        }
    }

    func resumeDeferredToolUse(
        _ pendingApproval: PendingToolApproval,
        decision: ClaudeToolApprovalDecision,
        sessionApprovalScope: ToolApprovalSessionScope?,
        updatedToolInput: String?
    ) async throws {
        let hasActiveTurn = state.turnState.isActive
        let hasRunningAgent = hasActiveTurn ? await agentsManager.isRunning(conversationId: conversation.id) : false
        let isResolvingLiveHookApproval = hasActiveTurn && hasRunningAgent
        let config = try makeSpawnConfig()
        let sessionApproval = sessionApprovalScope.flatMap {
            pendingApproval.request.sessionApprovalGrant(
                conversationId: conversation.id,
                providerId: config.providerId,
                scope: $0
            )
        }
        if !isResolvingLiveHookApproval {
            await prepareForSpawn(config: config)
        }
        await flushPendingSaveIfNeeded()
        if !isResolvingLiveHookApproval {
            resetSubscriptionTrackingForToolApprovalResume()
        }
        let liveResolution = try await resolveAgentToolApproval(
            pendingApproval,
            decision: decision,
            updatedToolInput: updatedToolInput,
            sessionApproval: sessionApproval,
            config: config
        )
        var relatedApprovalStatus = pendingApproval.status
        var resolvedPendingApproval = pendingApproval
        if decision == .allow,
           sessionApprovalScope != nil,
           !liveResolution.sessionApprovalEffective {
            relatedApprovalStatus = .approving
            resolvedPendingApproval = PendingToolApproval(
                request: pendingApproval.request,
                status: .approving
            )
        }
        updateResolvedToolApprovalState(
            resolvedPendingApproval,
            additionalApprovals: liveResolution.additionalApprovals,
            relatedApprovalStatus: relatedApprovalStatus
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

    func updateResolvedToolApprovalState(
        _ pendingApproval: PendingToolApproval,
        additionalApprovals: [ToolApprovalRequest],
        relatedApprovalStatus: ToolApprovalStatus
    ) {
        guard pendingApproval.request.toolName != "ExitPlanMode" else {
            persistRelatedToolApprovalStatuses(additionalApprovals, pendingStatus: relatedApprovalStatus)
            return
        }

        persistResolvedToolApproval(pendingApproval, refreshTranscript: false)
        persistRelatedToolApprovalStatuses(additionalApprovals, pendingStatus: relatedApprovalStatus)
        state.pendingToolApproval = nil
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

    func shouldPreservePendingToolApprovalBatch(replacingWith approval: ToolApprovalRequest) -> Bool {
        // Fallback deferral ends the local turn before delayed sibling hooks arrive.
        // Same-session, same-family approvals still belong to one user decision batch.
        guard let pendingApproval = state.pendingToolApproval,
              pendingApproval.status == .pending,
              pendingApproval.request.sessionId == approval.sessionId,
              ClaudeHookPolicy.canBatchPotentialApprovalToolCall(
                  toolName: approval.toolName,
                  with: [pendingApproval.request.toolName]
              ) else {
            return false
        }
        return true
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
    }

    func toolApprovalProviderId() -> String {
        conversation.provider ?? settingsService.current.defaultProvider
    }

    func supersedeUnresolvedToolApprovalRecords() {
        supersedeUnresolvedToolApprovalRecords(refreshTranscript: true)
    }

    func supersedeUnresolvedToolApprovalRecords(refreshTranscript: Bool) {
        let conversationID = conversation.id
        let unresolvedApprovalRecords = (try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                        $0.type == "tool_approval" &&
                        $0.toolApprovalStatus == nil
                }
            )
        )) ?? []
        guard !unresolvedApprovalRecords.isEmpty else {
            return
        }

        for approvalRecord in unresolvedApprovalRecords {
            approvalRecord.toolApprovalStatus = ToolApprovalStatus.superseded.rawValue
        }
        do {
            try modelContext.save()
            if refreshTranscript {
                refreshTranscriptForToolApprovalStatusChanges()
            }
        } catch {
            // Best-effort: transcript history is still preserved even if superseded
            // rows stay unresolved until the next successful save.
        }
    }

}

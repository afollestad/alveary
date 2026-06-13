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

    func approveToolUse(_ approval: ToolApprovalRequest) async throws {
        try await resolveToolUseApproval(
            toolUseId: approval.toolUseId,
            sessionId: approval.sessionId,
            decision: .allow
        )
    }

    func approveToolUseForSession(toolUseId: String, scope: ToolApprovalSessionScope) async throws {
        try await resolveToolUseApproval(
            toolUseId: toolUseId,
            decision: .allow,
            sessionApprovalScope: scope
        )
    }

    func approveToolUseForSession(_ approval: ToolApprovalRequest, scope: ToolApprovalSessionScope) async throws {
        try await resolveToolUseApproval(
            toolUseId: approval.toolUseId,
            sessionId: approval.sessionId,
            decision: .allow,
            sessionApprovalScope: scope
        )
    }

    func denyToolUse(toolUseId: String) async throws {
        try await resolveToolUseApproval(toolUseId: toolUseId, decision: .deny)
    }

    func denyToolUse(_ approval: ToolApprovalRequest) async throws {
        try await resolveToolUseApproval(
            toolUseId: approval.toolUseId,
            sessionId: approval.sessionId,
            decision: .deny
        )
    }

    func resolveExitPlanModeToolUseApproval(
        toolUseId: String,
        decision: ClaudeToolApprovalDecision
    ) async throws {
        try await resolveToolUseApproval(toolUseId: toolUseId, decision: decision)
    }

    func dismissPrompt(promptId: String) async throws {
        guard state.grouper.latestUnansweredPrompt?.id == promptId else {
            return
        }
        guard !state.isSendingMessage else {
            throw AgentError.spawnFailed("Wait for the current approval to finish before dismissing the prompt")
        }
        guard !state.isReconfiguringSession else {
            throw AgentError.spawnFailed("Wait for session changes to finish before dismissing the prompt")
        }

        let approvalCandidate = latestUnresolvedAskUserQuestionApprovalCandidate(promptId: promptId)
        let promptPendingApproval = pendingApprovalForPromptAnswer(
            promptId: promptId,
            approvalCandidate: approvalCandidate
        )

        state.isSendingMessage = true
        defer { state.isSendingMessage = false }

        guard let promptPendingApproval else {
            await dismissPromptWithoutApproval(promptId: promptId)
            return
        }

        if approvalCandidate?.shouldCheckSessionResolution != false,
           clearResolvedToolApprovalFromClaudeSessionIfNeeded(promptPendingApproval.request) != nil {
            completePromptDismissal(promptId: promptId)
            return
        }

        let resolvingApproval = PendingToolApproval(
            request: promptPendingApproval.request,
            status: .denying
        )
        state.pendingToolApproval = resolvingApproval
        beginPromptDismissResolution(promptId: promptId)
        defer { endPromptDismissResolution(promptId: promptId) }

        do {
            try await resumeDeferredToolUse(
                resolvingApproval,
                decision: .deny,
                sessionApprovalScope: nil,
                updatedToolInput: nil
            )
            completePromptDismissal(promptId: promptId)
        } catch {
            state.pendingToolApproval = PendingToolApproval(
                request: promptPendingApproval.request,
                status: .pending
            )
            state.lastTurnError = "Prompt dismiss failed: \(error.localizedDescription)"
            throw error
        }
    }

    func toolApprovalSelection(for approval: ToolApprovalRequest) async -> ToolApprovalSelection? {
        let providerId = toolApprovalProviderId()
        guard let storedSelection = await agentsManager.toolApprovalSelection(
            providerId: providerId,
            conversationId: conversation.id,
            sessionId: approval.sessionId
        ) else {
            return nil
        }

        let normalizedSelection = storedSelection.normalized(for: approval.supportedSessionApprovalScopes)
        if normalizedSelection != storedSelection {
            await agentsManager.recordToolApprovalSelection(
                normalizedSelection,
                providerId: providerId,
                conversationId: conversation.id,
                sessionId: approval.sessionId
            )
        }
        return normalizedSelection
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

        state.activeRuntimeActivityTurnId = nil
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
        clearPendingExitPlanModeFollowUpIfNeeded(toolUseId: pendingApproval.request.toolUseId)
        hydratePendingToolApprovalIfNeeded()
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
        hydratePendingToolApprovalIfNeeded()
        _ = enqueuePendingExitPlanModeFollowUpIfReady(clearedToolUseId: pendingApproval.request.toolUseId)
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
        hydratePendingToolApprovalIfNeeded()
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
            markVisibleTurnStarted()
            threadActivityRecorder.recordVisibleOutbound(conversationId: conversation.id)
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
        if state.pendingToolApproval?.request.toolUseId == approval.toolUseId,
           state.pendingToolApproval?.request.sessionId == approval.sessionId {
            state.pendingToolApproval = nil
            hydratePendingToolApprovalIfNeeded()
            _ = enqueuePendingExitPlanModeFollowUpIfReady(clearedToolUseId: approval.toolUseId)
        }
        return resolvedStatus
    }
}

private extension ConversationViewModel {
    func resolveToolUseApproval(
        toolUseId: String,
        sessionId: String? = nil,
        decision: ClaudeToolApprovalDecision,
        sessionApprovalScope: ToolApprovalSessionScope? = nil
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
                updatedToolInput: nil
            )
        } catch {
            state.pendingToolApproval = PendingToolApproval(request: pendingApproval.request, status: .pending)
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
        updatedToolInput: String?
    ) async throws {
        let hasActiveTurn = state.turnState.isActive
        let hasRunningAgent = hasActiveTurn ? await agentsManager.isRunning(conversationId: conversation.id) : false
        let isResolvingLiveHookApproval = hasActiveTurn && hasRunningAgent
        let config = try makeSpawnConfig(settingsSource: .currentContinuation)
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
}

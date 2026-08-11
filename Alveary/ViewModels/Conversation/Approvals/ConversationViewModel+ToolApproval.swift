import Foundation
import SwiftData

extension ConversationViewModel {
    /// Promotes the next unresolved approval into `pendingToolApproval` when nothing is on screen.
    ///
    /// Called on mount and after every resolution. The latter is what keeps unrelated approvals
    /// actionable: resolving one rehydrates the next rather than clearing the surface, so the
    /// composer stays blocked until every open approval has been handled. Rows the provider's own
    /// session already answered are persisted resolved here instead of being shown again.
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
        decision: ClaudeToolApprovalDecision,
        providerRestartConfig: AgentSpawnConfig? = nil
    ) async throws {
        try await resolveToolUseApproval(
            toolUseId: toolUseId,
            decision: decision,
            responseText: decision == .deny ? ExitPlanModeDenialPolicy.deniedResponseText : nil,
            providerRestartConfig: providerRestartConfig
        )
    }

    func dismissPrompt(promptId: String) async throws {
        guard state.grouper.latestUnansweredPrompt?.id == promptId else {
            return
        }
        try validatePromptDismissalAvailable()

        let approvalCandidate = latestUnresolvedAskUserQuestionApprovalCandidate(promptId: promptId)
        let promptPendingApproval = pendingApprovalForPromptAnswer(
            promptId: promptId,
            approvalCandidate: approvalCandidate
        )

        state.isSendingMessage = true
        defer { state.isSendingMessage = false }

        guard let promptPendingApproval else {
            try await dismissPromptWithoutApproval(promptId: promptId)
            return
        }

        if completeAlreadyResolvedPromptDismissalIfNeeded(
            promptId: promptId,
            promptPendingApproval: promptPendingApproval,
            shouldCheckSessionResolution: approvalCandidate?.shouldCheckSessionResolution != false
        ) {
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
        } catch {
            state.pendingToolApproval = PendingToolApproval(
                request: promptPendingApproval.request,
                status: .pending
            )
            state.lastTurnError = "Prompt dismiss failed: \(error.localizedDescription)"
            throw error
        }

        completePromptDismissal(promptId: promptId, handledApproval: promptPendingApproval.request)
        try await resolveSuppressedPromptDismissalApprovalsIfNeeded()
    }

    func validatePromptDismissalAvailable() throws {
        guard !state.isSendingMessage else {
            throw AgentError.spawnFailed("Wait for the current approval to finish before dismissing the prompt")
        }
        guard !state.isReconfiguringSession else {
            throw AgentError.spawnFailed("Wait for session changes to finish before dismissing the prompt")
        }
    }

    func completeAlreadyResolvedPromptDismissalIfNeeded(
        promptId: String,
        promptPendingApproval: PendingToolApproval,
        shouldCheckSessionResolution: Bool
    ) -> Bool {
        guard shouldCheckSessionResolution,
              clearResolvedToolApprovalFromClaudeSessionIfNeeded(promptPendingApproval.request) != nil else {
            return false
        }
        completePromptDismissal(
            promptId: promptId,
            handledApproval: promptPendingApproval.request,
            suppressDelayedFallout: false
        )
        return true
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
    /// Ends the local turn on a fallback `tool_deferred` stop, without treating it as a failure.
    ///
    /// Deferral means the provider is waiting on us, so `lastTurnError` is deliberately cleared
    /// rather than set — a banner here would report a stall as a fault. The controller's terminal
    /// boundary is *deferred* instead of completed, which is what keeps queued messages paused until
    /// the approval resumes and finishes the turn, and keeps the batch of delayed sibling approvals
    /// arriving after this point resolvable.
    func handleToolDeferredTokenIfNeeded(_ payload: TokenEventPayload) -> Bool {
        guard payload.stopReason == "tool_deferred" else {
            return false
        }

        state.activeRuntimeActivityTurnId = nil
        state.isCancellingTurn = false
        state.lastTurnInterrupted = false
        state.lastTurnError = nil
        state.deferControllerTerminalBoundary()
        return true
    }

    /// Takes a provider approval event and puts it on screen, unless it is already settled.
    ///
    /// A completed tool result is terminal for that approval, so a late or replayed event for the
    /// same tool must not recreate pending approval UI — the user would be asked to decide something
    /// the provider has already acted on.
    func handleToolApprovalRequested(_ approval: ToolApprovalRequest) -> Bool {
        guard state.pendingToolApproval?.request != approval else {
            return false
        }
        guard !toolApprovalAlreadyHasResult(approval) else {
            return false
        }

        if approval.toolName == "ExitPlanMode" {
            clearPendingExitPlanModeDenialState()
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
        clearPendingExitPlanModeRevisionGuidanceIfNeeded(toolUseId: pendingApproval.request.toolUseId)
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

    /// Retires the hook-owned approval row left behind once a prompt answer is accepted.
    ///
    /// A held `AskUserQuestion` hook produces an approval row beside the prompt; answering the
    /// prompt settles the interaction, so that row is `superseded` rather than approved or denied —
    /// the user decided the question, not the tool. Guarded on the row still being `.pending` and
    /// still being the one on screen, so a newer approval that arrived meanwhile is not retired with
    /// it. `hydratePendingToolApprovalIfNeeded()` then brings forward whatever is genuinely still open.
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
        let continuation = beginPromptAnswerContinuation()
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
            restorePromptAnswerContinuation(continuation)
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

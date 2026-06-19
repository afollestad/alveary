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
        try await resolveToolUseApproval(
            toolUseId: toolUseId,
            decision: decision,
            responseText: decision == .deny ? ExitPlanModeDenialPolicy.deniedResponseText : nil
        )
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
            try await dismissPromptWithoutApproval(promptId: promptId)
            return
        }

        if approvalCandidate?.shouldCheckSessionResolution != false,
           clearResolvedToolApprovalFromClaudeSessionIfNeeded(promptPendingApproval.request) != nil {
            completePromptDismissal(promptId: promptId, suppressDelayedFallout: false)
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

        completePromptDismissal(promptId: promptId)
        try await resolveSuppressedPromptDismissalApprovalsIfNeeded()
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

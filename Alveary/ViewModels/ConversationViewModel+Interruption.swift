import Foundation
import SwiftData

struct PromptAnswerContinuationSnapshot {
    let wasTurnActive: Bool
    let turnActivityVisibility: AgentTurnActivityVisibility
    let hasRecordedLocalTurnEndActivity: Bool
    let wasLastTurnInterrupted: Bool
    let wasDismissalSuppressionActive: Bool
    let wasDismissalReplacementMarked: Bool
    let wasDismissalTerminalSeen: Bool
}

extension ConversationViewModel {
    func beginPromptDismissResolution(promptId: String) {
        // Claude/Codex can emit fallback text or a follow-up prompt before the host-side
        // denial call returns. Suppress that direct in-flight fallout here; successful
        // dismissals also arm a terminal-bounded filter for delayed provider events.
        if promptDismissalsResolving.isEmpty {
            promptDismissalSuppressedApprovals.removeAll()
            promptDismissalNewOutboundTurnStarted = false
            promptDismissalTerminalFalloutSeen = false
        }
        promptDismissalsResolving.insert(promptId)
        state.activeRuntimeActivityTurnId = nil
        state.lastTurnError = nil
        state.clearStreamingText()
    }

    func endPromptDismissResolution(promptId: String) {
        promptDismissalsResolving.remove(promptId)
    }

    func shouldSuppressPromptDismissalEvent(_ event: ConversationEvent) -> Bool {
        guard !promptDismissalsResolving.isEmpty else {
            return false
        }
        if case .sessionInit = event {
            return false
        }

        handleSuppressedPromptApproval(from: event, deferResolution: true)
        if event.endsPromptDismissalFalloutSuppression {
            promptDismissalTerminalFalloutSeen = true
        }
        state.activeRuntimeActivityTurnId = nil
        state.lastTurnError = nil
        state.clearStreamingText()
        return true
    }

    func shouldSuppressPromptDismissalFallout(_ event: ConversationEvent) -> Bool {
        guard promptDismissalFalloutSuppressionActive else {
            return false
        }
        if case .sessionInit = event {
            return false
        }
        if promptDismissalNewOutboundTurnStarted, event.startsPromptDismissalReplacementTurn {
            clearPromptDismissalFalloutSuppression()
            return false
        }

        handleSuppressedPromptApproval(from: event, deferResolution: false)
        let shouldSuppress = event.isPromptDismissalFallout
        if event.endsPromptDismissalFalloutSuppression {
            clearPromptDismissalFalloutSuppression()
        }
        guard shouldSuppress else {
            return false
        }

        state.lastTurnError = nil
        return true
    }

    func dismissPromptWithoutApproval(promptId: String) async throws {
        let shouldSuppressDelayedFallout = isAgentActivelyWorking
        beginPromptDismissResolution(promptId: promptId)
        defer { endPromptDismissResolution(promptId: promptId) }

        if shouldSuppressDelayedFallout {
            await agentsManager.cancelTurn(conversationId: conversation.id)
        }
        completePromptDismissal(promptId: promptId, suppressDelayedFallout: shouldSuppressDelayedFallout)
        try await resolveSuppressedPromptDismissalApprovalsIfNeeded()
    }

    func completePromptDismissal(promptId: String, suppressDelayedFallout: Bool = true) {
        if suppressDelayedFallout, !promptDismissalTerminalFalloutSeen {
            promptDismissalFalloutSuppressionActive = true
        }
        markPromptDismissInterruption()
        recordPromptHandled(promptId: promptId)
    }

    @discardableResult
    func markPromptDismissalNewOutboundTurnStarted() -> Bool {
        guard promptDismissalFalloutSuppressionActive else {
            return false
        }
        promptDismissalNewOutboundTurnStarted = true
        return true
    }

    func restorePromptDismissalNewOutboundTurnStartedIfNeeded(_ wasMarked: Bool) {
        guard wasMarked, promptDismissalFalloutSuppressionActive else {
            return
        }
        promptDismissalNewOutboundTurnStarted = false
    }

    func clearPromptDismissalFalloutSuppression() {
        promptDismissalFalloutSuppressionActive = false
        promptDismissalNewOutboundTurnStarted = false
        promptDismissalTerminalFalloutSeen = false
    }

    func beginPromptAnswerContinuation() -> PromptAnswerContinuationSnapshot {
        let snapshot = PromptAnswerContinuationSnapshot(
            wasTurnActive: state.turnState.isActive,
            turnActivityVisibility: state.currentTurnActivityVisibility,
            hasRecordedLocalTurnEndActivity: state.hasRecordedLocalTurnEndActivity,
            wasLastTurnInterrupted: state.lastTurnInterrupted,
            wasDismissalSuppressionActive: promptDismissalFalloutSuppressionActive,
            wasDismissalReplacementMarked: promptDismissalNewOutboundTurnStarted,
            wasDismissalTerminalSeen: promptDismissalTerminalFalloutSeen
        )
        clearPromptDismissalFalloutSuppression()
        state.lastTurnInterrupted = false
        markVisibleTurnStarted()
        state.turnState.beginTurn()
        return snapshot
    }

    func restorePromptAnswerContinuation(_ snapshot: PromptAnswerContinuationSnapshot) {
        if !snapshot.wasTurnActive {
            state.endTurn()
        }
        state.currentTurnActivityVisibility = snapshot.turnActivityVisibility
        state.hasRecordedLocalTurnEndActivity = snapshot.hasRecordedLocalTurnEndActivity
        state.lastTurnInterrupted = snapshot.wasLastTurnInterrupted
        promptDismissalFalloutSuppressionActive = snapshot.wasDismissalSuppressionActive
        promptDismissalNewOutboundTurnStarted = snapshot.wasDismissalReplacementMarked
        promptDismissalTerminalFalloutSeen = snapshot.wasDismissalTerminalSeen
    }

    func handleSuppressedPromptApproval(from event: ConversationEvent, deferResolution: Bool) {
        guard case .toolApprovalRequested(let approval) = event,
              approval.isAppNativeInteractionPrompt,
              state.pendingToolApproval?.request != approval,
              !promptDismissalHandledApprovalKeys.contains(approval.promptDismissalKey),
              !suppressedPromptApprovalAlreadyResolved(approval) else {
            return
        }

        if deferResolution {
            appendSuppressedPromptDismissalApproval(approval)
        } else {
            scheduleSuppressedPromptApprovalResolution(approval)
        }
    }

    func appendSuppressedPromptDismissalApproval(_ approval: ToolApprovalRequest) {
        guard !promptDismissalSuppressedApprovals.contains(where: { existing in
            existing.sessionId == approval.sessionId && existing.toolUseId == approval.toolUseId
        }) else {
            return
        }

        promptDismissalSuppressedApprovals.append(approval)
    }

    func suppressedPromptApprovalAlreadyResolved(_ approval: ToolApprovalRequest) -> Bool {
        let conversationID = conversation.id
        let toolUseId = approval.toolUseId
        let sessionId = approval.sessionId
        return ((try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                        $0.type == "tool_approval" &&
                        $0.toolId == toolUseId &&
                        $0.content == sessionId &&
                        $0.toolApprovalStatus != nil
                }
            )
        ).isEmpty == false) ?? false)
    }

    func resolveSuppressedPromptDismissalApprovalsIfNeeded() async throws {
        guard !promptDismissalSuppressedApprovals.isEmpty else {
            return
        }

        let approvals = promptDismissalSuppressedApprovals
        promptDismissalSuppressedApprovals.removeAll()
        for approval in approvals {
            try await denySuppressedPromptApproval(approval)
            promptDismissalHandledApprovalKeys.insert(approval.promptDismissalKey)
        }
    }

    func scheduleSuppressedPromptApprovalResolution(_ approval: ToolApprovalRequest) {
        let key = approval.promptDismissalKey
        guard promptDismissalHandledApprovalKeys.insert(key).inserted else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                try await denySuppressedPromptApproval(approval)
            } catch {
                promptDismissalHandledApprovalKeys.remove(key)
                state.lastTurnError = "Prompt follow-up cancellation failed: \(error.localizedDescription)"
            }
        }
    }

    func denySuppressedPromptApproval(_ approval: ToolApprovalRequest) async throws {
        let config = try makeSpawnConfig(settingsSource: .currentContinuation)
        _ = try await agentsManager.resolveToolApproval(AgentToolApprovalResolutionRequest(
            conversationId: conversation.id,
            approval: approval,
            resolution: ClaudeToolApprovalResolution(decision: .deny),
            additionalApprovals: [],
            sessionApproval: nil,
            config: config
        ))
    }

    func markTranscriptActivityInterrupted() {
        state.grouper.markIncompleteTranscriptActivityInterrupted()
    }

    func markPromptDismissInterruption() {
        state.activeRuntimeActivityTurnId = nil
        state.isAutomaticSessionHandoffPending = false
        state.isCancellingTurn = false
        state.lastTurnError = nil
        state.lastTurnInterrupted = true
        markTranscriptActivityInterrupted()
        state.clearStreamingText()
        state.endTurn()
        recordLocalVisibleTurnEndedIfNeeded()
    }

    func isConfirmedTurnInterruption(
        isError: Bool,
        stopReason: String?,
        permissionDenials: [PermissionDenialSummary]
    ) -> Bool {
        guard isError,
              state.isCancellingTurn,
              permissionDenials.isEmpty else {
            return false
        }

        let normalizedStopReason = stopReason?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard let normalizedStopReason,
              !normalizedStopReason.isEmpty else {
            return true
        }

        if normalizedStopReason.contains("interrupt") || normalizedStopReason.contains("cancel") {
            return true
        }

        // When a turn is cancelled mid-tool-use, Claude emits `is_error: true` alongside a
        // standard `stop_reason` value ("tool_use", "end_turn", etc.). Those reasons are not
        // genuine failures — treat them as interruptions rather than raw error text.
        return claudeNormalStopReasons.contains(normalizedStopReason)
    }
}

private let claudeNormalStopReasons: Set<String> = [
    "tool_use",
    "end_turn",
    "pause_turn",
    "max_tokens",
    "stop_sequence",
    "refusal"
]

private extension ConversationEvent {
    var startsPromptDismissalReplacementTurn: Bool {
        if case .runtimeActivity(.active, _, _) = self {
            return true
        }
        return false
    }

    var isPromptDismissalFallout: Bool {
        switch self {
        case .message,
             .messageChunk,
             .thinking,
             .toolCall,
             .toolResult,
             .toolApprovalRequested,
             .toolApprovalFailed,
             .tokens,
             .runtimeActivity,
             .stop,
             .error,
             .permissionModeChanged,
             .collaborationModeChanged:
            return true
        default:
            return false
        }
    }

    var endsPromptDismissalFalloutSuppression: Bool {
        if let payload = TokenEventPayload(self) {
            return payload.permissionDenials.isEmpty && payload.completesTurn
        }
        switch self {
        case .runtimeActivity(.idle, _, _),
             .stop,
             .error:
            return true
        default:
            return false
        }
    }
}

private extension ToolApprovalRequest {
    var promptDismissalKey: ClaudeToolApprovalKey {
        ClaudeToolApprovalKey(sessionId: sessionId, toolUseId: toolUseId)
    }
}

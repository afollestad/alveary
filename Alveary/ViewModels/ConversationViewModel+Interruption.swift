import Foundation

extension ConversationViewModel {
    func beginPromptDismissResolution(promptId: String) {
        // Claude/Codex can emit fallback text or a follow-up prompt before the host-side
        // denial call returns. Suppress only that in-flight fallout; do not leave a
        // durable marker around that can swallow events from the next user turn.
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

        state.activeRuntimeActivityTurnId = nil
        state.lastTurnError = nil
        state.clearStreamingText()
        return true
    }

    func dismissPromptWithoutApproval(promptId: String) async {
        beginPromptDismissResolution(promptId: promptId)
        defer { endPromptDismissResolution(promptId: promptId) }

        if isAgentActivelyWorking {
            await agentsManager.cancelTurn(conversationId: conversation.id)
        }
        completePromptDismissal(promptId: promptId)
    }

    func completePromptDismissal(promptId: String) {
        markPromptDismissInterruption()
        recordPromptHandled(promptId: promptId)
    }

    func markTranscriptToolsInterrupted() {
        state.grouper.markIncompleteToolsInterrupted()
    }

    func markPromptDismissInterruption() {
        state.activeRuntimeActivityTurnId = nil
        state.isAutomaticSessionHandoffPending = false
        state.isCancellingTurn = false
        state.lastTurnError = nil
        state.lastTurnInterrupted = true
        markTranscriptToolsInterrupted()
        state.clearStreamingText()
        state.turnState.endTurn()
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

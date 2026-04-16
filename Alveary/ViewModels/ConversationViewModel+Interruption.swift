import Foundation

extension ConversationViewModel {
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

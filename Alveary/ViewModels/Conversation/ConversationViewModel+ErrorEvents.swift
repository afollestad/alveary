import Foundation

/// How a turn's failure is classified before anything is persisted.
///
/// Split from `ConversationViewModel+EventHandling.swift` to keep that file inside SwiftLint's
/// `file_length` budget; the dispatch switch there routes into these.
extension ConversationViewModel {
    func shouldPersistErrorEvent(message: String) -> Bool {
        state.activeRuntimeActivityTurnId = nil
        state.clearStreamingText()
        if shouldSuppressInterruptedError(message) {
            state.isCancellingTurn = false
            state.endTurn()
            scheduleSave()
            return false
        }

        state.isAutomaticSessionHandoffPending = false
        state.isCancellingTurn = false
        state.lastTurnInterrupted = false
        controllerTerminalFailureMessage = normalizedTurnErrorMessage(message, fallback: "Agent turn failed")
        state.lastTurnError = nil
        state.endTurn()
        return true
    }

    /// Records the sign-in notice and persists nothing; the `.error` the mapper emits alongside it is
    /// what lands in the transcript.
    func shouldPersistProviderAuthenticationRequiredEvent(message: String) -> Bool {
        state.providerAuthenticationFailure = normalizedTurnErrorMessage(message, fallback: "Agent turn failed")
        return false
    }

    func shouldSuppressInterruptedError(_ message: String) -> Bool {
        guard state.lastTurnInterrupted, !state.turnState.isActive else {
            return false
        }
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedMessage.contains("interrupt") ||
            normalizedMessage.contains("cancel") ||
            normalizedMessage.contains("no active turn")
    }

    func normalizedTurnErrorMessage(_ message: String, fallback: String) -> String {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedMessage.isEmpty ? fallback : trimmedMessage
    }
}

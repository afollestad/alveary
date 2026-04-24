import Foundation

extension DefaultAgentsManager {
    func canTriggerNotification(_ event: ConversationEvent) -> Bool {
        switch event {
        case .tokens, .stop, .notification, .error:
            return true
        default:
            return false
        }
    }

    func notificationEvent(for event: ConversationEvent, conversationId: String) async -> ConversationEvent {
        guard case .tokens(let input, let output, let cacheRead, let isError, let stopReason, _, _, let permissionDenials) = event else {
            return event
        }

        let payload = TokenEventPayload(
            input: input,
            output: output,
            cacheRead: cacheRead,
            isError: isError,
            stopReason: stopReason,
            permissionDenials: permissionDenials
        )

        return await MainActor.run {
            let state = conversationState(for: conversationId)
            return state.synthesizedSlashCommandFailureNotice(for: payload).map { .error(message: $0) } ?? event
        }
    }

    func shouldNotify(
        for event: ConversationEvent,
        notificationEvent: ConversationEvent,
        conversationId: String
    ) async -> Bool {
        if case .tokens(_, _, _, true, let stopReason, _, _, let permissionDenials) = event,
           permissionDenials.isEmpty,
           ConversationInterruption.isRequestInterruptedByUserReason(stopReason) {
            return false
        }

        guard notificationEvent == event,
              case .tokens(_, _, _, let isError, _, _, _, let permissionDenials) = event,
              !isError,
              permissionDenials.isEmpty else {
            return true
        }

        return await MainActor.run {
            let state = conversationState(for: conversationId)
            return state.messageQueue.peekNext() == nil && state.inFlightQueuedMessageID == nil
        }
    }

    func tokenStatusSignal(
        isError: Bool,
        stopReason: String?,
        permissionDenials: [PermissionDenialSummary]
    ) -> ActivitySignal {
        guard isError else {
            return .idle
        }

        if permissionDenials.isEmpty,
           ConversationInterruption.isRequestInterruptedByUserReason(stopReason) {
            return .idle
        }

        return .error
    }
}

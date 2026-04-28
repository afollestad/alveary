import Foundation

extension DefaultAgentsManager {
    func canTriggerNotification(_ event: ConversationEvent) -> Bool {
        switch event {
        case .tokens, .toolApprovalRequested, .stop, .notification, .error:
            return true
        default:
            return false
        }
    }

    func notificationEvent(for event: ConversationEvent, conversationId: String) async -> ConversationEvent {
        guard let payload = TokenEventPayload(event) else {
            return event
        }

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
        if case .tokens(_, _, _, _, true, let stopReason, _, _, _, _, let permissionDenials) = event,
           permissionDenials.isEmpty,
           ConversationInterruption.isRequestInterruptedByUserReason(stopReason) {
            return false
        }

        if shouldSuppressNonTerminalTokenNotification(for: event, notificationEvent: notificationEvent) {
            return false
        }

        if shouldSuppressResolvedPermissionDenialNotification(for: event, conversationId: conversationId) {
            return false
        }

        clearPendingUserActionNotificationIfNeeded(for: event, conversationId: conversationId)

        if case .toolApprovalRequested = event {
            return shouldNotifyPendingUserAction(conversationId: conversationId)
        }

        guard notificationEvent == event,
              case .tokens(_, _, _, _, let isError, _, _, _, _, _, let permissionDenials) = event,
              !isError,
              permissionDenials.isEmpty else {
            return true
        }

        return await MainActor.run {
            let state = conversationState(for: conversationId)
            return state.messageQueue.peekNext() == nil && state.inFlightQueuedMessageID == nil
        }
    }

    private func shouldSuppressNonTerminalTokenNotification(
        for event: ConversationEvent,
        notificationEvent: ConversationEvent
    ) -> Bool {
        guard notificationEvent == event,
              case .tokens(_, _, _, _, let isError, let stopReason, _, _, _, _, let permissionDenials) = event else {
            return false
        }

        // Usage updates and deferred-tool stops are progress/waiting states, not completed turns.
        if stopReason == ConversationEvent.interimUsageStopReason {
            return true
        }
        return stopReason == "tool_deferred" && !isError && permissionDenials.isEmpty
    }

    private func shouldSuppressResolvedPermissionDenialNotification(
        for event: ConversationEvent,
        conversationId: String
    ) -> Bool {
        guard case .tokens(_, _, _, _, _, _, _, _, _, _, let permissionDenials) = event,
              !permissionDenials.isEmpty,
              var deniedToolUseIds = deniedToolUseIdsByConversation[conversationId] else {
            return false
        }

        let deniedPermissionIds = permissionDenials.compactMap(\.toolUseId)
        guard deniedPermissionIds.count == permissionDenials.count,
              deniedPermissionIds.allSatisfy(deniedToolUseIds.contains) else {
            return false
        }

        deniedToolUseIds.subtract(deniedPermissionIds)
        deniedToolUseIdsByConversation[conversationId] = deniedToolUseIds.isEmpty ? nil : deniedToolUseIds
        return true
    }

    private func clearPendingUserActionNotificationIfNeeded(
        for event: ConversationEvent,
        conversationId: String
    ) {
        guard isTerminalNotificationBoundary(event) else {
            return
        }
        eventBuffers[conversationId]?.hasSentPendingUserActionNotification = false
    }

    private func isTerminalNotificationBoundary(_ event: ConversationEvent) -> Bool {
        switch event {
        case .stop, .error:
            return true
        case .tokens(_, _, _, _, let isError, let stopReason, _, _, _, _, let permissionDenials):
            if isError || !permissionDenials.isEmpty {
                return true
            }
            return stopReason != ConversationEvent.interimUsageStopReason && stopReason != "tool_deferred"
        default:
            return false
        }
    }

    private func shouldNotifyPendingUserAction(conversationId: String) -> Bool {
        guard let buffer = eventBuffers[conversationId] else {
            return true
        }

        // Parallel live hooks can surface as several approval rows, but one user decision surface.
        guard !buffer.hasSentPendingUserActionNotification else {
            return false
        }
        buffer.hasSentPendingUserActionNotification = true
        return true
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

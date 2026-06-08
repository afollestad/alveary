import AgentCLIKit
import Foundation

extension DefaultAgentsManager {
    func handleStreamEvent(
        _ event: ConversationEvent,
        conversationId: String,
        generation: UUID,
        providerId: String,
        allowAfterDeferredStop: Bool = false
    ) async {
        guard let managedBuffer = eventBuffers[conversationId],
              managedBuffer.generation == generation,
              managedBuffer.acceptsLiveEvents || allowAfterDeferredStop else {
            return
        }
        managedBuffer.buffer.push(event)
        managedBuffer.observedEventCount += 1

        await handleConversationLifecycleEvent(event, conversationId: conversationId)
        await handleRuntimeStatusEvent(event, conversationId: conversationId, generation: generation)

        guard canTriggerNotification(event) else {
            return
        }

        let notificationEvent = await notificationEvent(for: event, conversationId: conversationId)
        let shouldNotify = await shouldNotify(for: event, notificationEvent: notificationEvent, conversationId: conversationId)

        guard shouldNotify else {
            return
        }

        await notificationManager.handleEvent(notificationEvent, conversationId: conversationId)
    }

    func finishStreamBufferIfCurrent(conversationId: String, generation: UUID) {
        guard let managedBuffer = eventBuffers[conversationId], managedBuffer.generation == generation else {
            return
        }
        managedBuffer.buffer.finishAll()
    }

    private func handleRuntimeStatusEvent(
        _ event: ConversationEvent,
        conversationId: String,
        generation: UUID
    ) async {
        switch event {
        case .tokens(_, _, _, _, let isError, let stopReason, _, _, _, _, let permissionDenials):
            await handleTokenStatus(
                isError: isError,
                stopReason: stopReason,
                permissionDenials: permissionDenials,
                conversationId: conversationId
            )
            handleToolDeferredStopIfNeeded(
                stopReason: stopReason,
                conversationId: conversationId,
                generation: generation
            )
        case .toolApprovalFailed(let failure):
            handleToolApprovalFailureStatus(failure, conversationId: conversationId)
        case .toolApprovalRequested:
            handleToolApprovalRequestedStatus(conversationId: conversationId)
        case .error:
            if cancelledInteractionsByConversation[conversationId] != nil {
                updateStatus(.idle, for: conversationId)
            } else {
                updateStatus(.error, for: conversationId)
            }
        case .runtimeActivity(_, _, let outcome):
            handleRuntimeActivityStatus(outcome, conversationId: conversationId)
        default:
            break
        }
    }

    private func handleRuntimeActivityStatus(
        _ outcome: ConversationRuntimeActivityOutcome,
        conversationId: String
    ) {
        if case .failed = outcome,
           cancelledInteractionsByConversation[conversationId] != nil {
            updateStatus(.idle, for: conversationId)
            return
        }
        guard case .failed = outcome,
              eventBuffers[conversationId]?.acceptsLiveEvents == true,
              status(for: conversationId) != .waitingForUser else {
            return
        }
        updateStatus(.error, for: conversationId)
    }

    private func handleToolApprovalFailureStatus(
        _ failure: ToolApprovalFailure,
        conversationId: String
    ) {
        if cancelledInteractionsByConversation[conversationId] != nil {
            eventBuffers[conversationId]?.hasSentPendingUserActionNotification = false
            updateStatus(.idle, for: conversationId)
            return
        }
        if failure.toolUseId != nil {
            decrementPendingLiveToolApprovals(conversationId: conversationId, count: 1)
            eventBuffers[conversationId]?.hasSentPendingUserActionNotification = false
        }
        if status(for: conversationId) == .waitingForUser {
            updateStatus(.busy, for: conversationId)
        }
    }

    private func handleToolApprovalRequestedStatus(conversationId: String) {
        if cancelledInteractionsByConversation[conversationId] != nil {
            updateStatus(.idle, for: conversationId)
            return
        }

        cancelledInteractionsByConversation.removeValue(forKey: conversationId)
        updateStatus(.waitingForUser, for: conversationId)
    }

    private func handleTokenStatus(
        isError: Bool,
        stopReason: String?,
        permissionDenials: [PermissionDenialSummary],
        conversationId: String
    ) async {
        guard stopReason != ConversationEvent.interimUsageStopReason else {
            return
        }

        if cancelledInteractionsByConversation[conversationId] != nil {
            updateStatus(.idle, for: conversationId)
            return
        }

        let isWaitingOnDeferredPrompt = stopReason == "tool_deferred" &&
            !isError &&
            permissionDenials.isEmpty
        if isWaitingOnDeferredPrompt {
            updateStatus(.waitingForUser, for: conversationId)
            return
        }

        if await isAgentCLIKitTurnStillActive(
            isError: isError,
            permissionDenials: permissionDenials,
            conversationId: conversationId
        ) {
            updateStatus(.busy, for: conversationId)
            return
        }

        updateStatus(
            tokenStatusSignal(isError: isError, stopReason: stopReason, permissionDenials: permissionDenials),
            for: conversationId
        )
    }

    private func isAgentCLIKitTurnStillActive(
        isError: Bool,
        permissionDenials: [PermissionDenialSummary],
        conversationId: String
    ) async -> Bool {
        guard !isError, permissionDenials.isEmpty else {
            return false
        }
        let services = agentCLIKitServices
        let status = await services.runtime.status(conversationId: services.hostAdapter.conversationId(conversationId))
        if let status {
            agentCLIKitStatuses[conversationId] = status
            return status.isTurnActive
        }
        return agentCLIKitStatuses[conversationId]?.isTurnActive == true
    }

    private func handleToolDeferredStopIfNeeded(
        stopReason: String?,
        conversationId: String,
        generation: UUID
    ) {
        guard stopReason == "tool_deferred",
              eventBuffers[conversationId]?.hasDeferredToolStop != true else {
            return
        }

        eventBuffers[conversationId]?.hasDeferredToolStop = true
        eventBuffers[conversationId]?.acceptsLiveEvents = false
        eventBuffers[conversationId]?.allowsReplay = true
        Task { [weak self] in
            await self?.stopAgentCLIKitDeferredRuntimeIfCurrent(
                conversationId: conversationId,
                generation: generation
            )
        }
    }

    private func handleConversationLifecycleEvent(
        _ event: ConversationEvent,
        conversationId: String
    ) async {
        let sessionId: String?
        switch event {
        case .sessionInit(let value),
             .providerSessionMetadataChanged(let value, _):
            sessionId = value
        default:
            sessionId = nil
        }

        if let sessionId {
            await updateConversationSessionID(sessionId, conversationId: conversationId)
        }
    }

    func suppressCancelledInteractionStatusIfNeeded(
        _ status: AgentCLIKit.AgentRuntimeStatus,
        conversationId: String
    ) -> Bool {
        guard let cancelledInteraction = cancelledInteractionsByConversation[conversationId] else {
            return false
        }

        if let agentGeneration = cancelledInteraction.agentGeneration,
           agentGeneration != status.generation {
            cancelledInteractionsByConversation.removeValue(forKey: conversationId)
            return false
        }

        if status.waitingState != .idle {
            updateStatus(.idle, for: conversationId)
            return true
        }

        switch status.state {
        case .starting, .running:
            guard status.isTurnActive else {
                return false
            }
            updateStatus(.idle, for: conversationId)
            return true
        case .failed, .cancelled, .exited:
            cancelledInteractionsByConversation.removeValue(forKey: conversationId)
            updateStatus(.idle, for: conversationId)
            return true
        }
    }
}

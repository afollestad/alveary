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
        await handleRuntimeStatusEvent(event, conversationId: conversationId)

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
        conversationId: String
    ) async {
        switch event {
        case .tokens:
            guard let payload = TokenEventPayload(event) else {
                return
            }
            await handleTokenStatus(payload, conversationId: conversationId)
            handleToolDeferredStopIfNeeded(
                stopReason: payload.stopReason,
                conversationId: conversationId
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
        case .runtimeActivity(let state, _, let outcome):
            handleRuntimeActivityStatus(state, outcome: outcome, conversationId: conversationId)
        default:
            break
        }
    }

    private func handleRuntimeActivityStatus(
        _ state: ConversationRuntimeActivityState,
        outcome: ConversationRuntimeActivityOutcome,
        conversationId: String
    ) {
        // Cancelled interactions stay idle; activity from the cancelled turn must
        // not reopen busy or error state. Do not clear the marker here — only new
        // sends, generations, or approval requests may do that.
        if cancelledInteractionsByConversation[conversationId] != nil {
            if case .failed = outcome {
                updateStatus(.idle, for: conversationId)
            }
            return
        }
        guard eventBuffers[conversationId]?.acceptsLiveEvents == true else {
            return
        }
        if case .failed = outcome {
            guard status(for: conversationId) != .waitingForUser else {
                return
            }
            updateStatus(.error, for: conversationId)
            return
        }
        switch state {
        case .active:
            // Pending approvals own the waiting state; parallel tool activity must
            // not flip a waiting conversation back to busy.
            guard status(for: conversationId) != .waitingForUser else {
                return
            }
            updateStatus(.busy, for: conversationId)
        case .idle:
            // Terminal token rows own the final idle/stopped/error signal; only
            // release a busy set by activity so error/waiting states are preserved.
            guard status(for: conversationId) == .busy else {
                return
            }
            updateStatus(.idle, for: conversationId)
        }
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
        _ payload: TokenEventPayload,
        conversationId: String
    ) async {
        guard payload.stopReason != ConversationEvent.interimUsageStopReason else {
            return
        }

        if cancelledInteractionsByConversation[conversationId] != nil {
            updateStatus(.idle, for: conversationId)
            return
        }

        let isWaitingOnDeferredPrompt = payload.stopReason == "tool_deferred" &&
            !payload.isError &&
            payload.permissionDenials.isEmpty
        if isWaitingOnDeferredPrompt {
            updateStatus(.waitingForUser, for: conversationId)
            return
        }

        guard payload.completesTurn else {
            return
        }

        if await isAgentCLIKitTurnStillActive(
            isError: payload.isError,
            permissionDenials: payload.permissionDenials,
            conversationId: conversationId
        ) {
            updateStatus(.busy, for: conversationId)
            return
        }

        updateStatus(
            tokenStatusSignal(
                isError: payload.isError,
                stopReason: payload.stopReason,
                permissionDenials: payload.permissionDenials
            ),
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
        conversationId: String
    ) {
        guard stopReason == "tool_deferred",
              eventBuffers[conversationId]?.hasDeferredToolStop != true else {
            return
        }

        // AgentCLIKit owns deferred-stop teardown: it closes stdin so the provider can flush its
        // deferred-tool session records before exiting, then force kills after a grace period.
        // Killing from here raced those writes and broke deferred-approval resumes.
        eventBuffers[conversationId]?.hasDeferredToolStop = true
        eventBuffers[conversationId]?.acceptsLiveEvents = false
        eventBuffers[conversationId]?.allowsReplay = true
    }

    private func handleConversationLifecycleEvent(
        _ event: ConversationEvent,
        conversationId: String
    ) async {
        let sessionId: String?
        switch event {
        case .sessionInit(let value),
             .providerSessionMetadataChanged(let value, _, _):
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

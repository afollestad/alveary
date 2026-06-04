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
            updateStatus(.waitingForUser, for: conversationId)
        case .error:
            updateStatus(.error, for: conversationId)
        default:
            break
        }
    }

    private func handleToolApprovalFailureStatus(
        _ failure: ToolApprovalFailure,
        conversationId: String
    ) {
        if failure.toolUseId != nil {
            decrementPendingLiveToolApprovals(conversationId: conversationId, count: 1)
            eventBuffers[conversationId]?.hasSentPendingUserActionNotification = false
        }
        if status(for: conversationId) == .waitingForUser {
            updateStatus(.busy, for: conversationId)
        }
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
        if case .sessionInit(let sessionId) = event, let sessionId {
            await updateConversationSessionID(sessionId, conversationId: conversationId)
        }
    }
}

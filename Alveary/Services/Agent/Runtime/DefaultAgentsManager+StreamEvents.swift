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

        await handleConversationLifecycleEvent(event, conversationId: conversationId)
        handleRuntimeStatusEvent(event, conversationId: conversationId, generation: generation)

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
    ) {
        switch event {
        case .tokens(_, _, _, _, let isError, let stopReason, _, _, _, _, let permissionDenials):
            handleTokenStatus(
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
        case .toolApprovalRequested(let request):
            if request.toolName == "AskUserQuestion" {
                updateStatus(.waitingForUser, for: conversationId)
            }
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
        }
        if failure.toolName == "AskUserQuestion",
           status(for: conversationId) == .waitingForUser {
            updateStatus(.busy, for: conversationId)
        }
    }

    private func handleTokenStatus(
        isError: Bool,
        stopReason: String?,
        permissionDenials: [PermissionDenialSummary],
        conversationId: String
    ) {
        guard stopReason != ConversationEvent.interimUsageStopReason else {
            return
        }

        let isWaitingOnDeferredPrompt = stopReason == "tool_deferred" &&
            !isError &&
            permissionDenials.isEmpty &&
            status(for: conversationId) == .waitingForUser
        guard !isWaitingOnDeferredPrompt else {
            return
        }

        updateStatus(
            tokenStatusSignal(isError: isError, stopReason: stopReason, permissionDenials: permissionDenials),
            for: conversationId
        )
    }

    private func handleToolDeferredStopIfNeeded(
        stopReason: String?,
        conversationId: String,
        generation: UUID
    ) {
        guard stopReason == "tool_deferred",
              let pid = processes[conversationId]?.processIdentifier,
              eventBuffers[conversationId]?.hasDeferredToolStop != true else {
            return
        }

        eventBuffers[conversationId]?.hasDeferredToolStop = true
        eventBuffers[conversationId]?.acceptsLiveEvents = false
        Task { [weak self] in
            await self?.stopDeferredRuntimeIfCurrent(
                conversationId: conversationId,
                generation: generation,
                pid: pid
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

        if case .permissionModeChanged(let permissionMode) = event {
            await claudeHookServer.updatePermissionMode(permissionMode, for: conversationId)
        }
    }
}

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

        switch event {
        case .tokens(_, _, _, _, let isError, let stopReason, _, _, _, _, let permissionDenials):
            updateStatus(
                tokenStatusSignal(isError: isError, stopReason: stopReason, permissionDenials: permissionDenials),
                for: conversationId
            )
            if stopReason == "tool_deferred",
               let pid = processes[conversationId]?.processIdentifier {
                guard eventBuffers[conversationId]?.hasDeferredToolStop != true else {
                    break
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
        case .toolApprovalFailed(let failure):
            if failure.toolUseId != nil {
                decrementPendingLiveToolApprovals(conversationId: conversationId, count: 1)
            }
        case .error:
            updateStatus(.error, for: conversationId)
        default:
            break
        }

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

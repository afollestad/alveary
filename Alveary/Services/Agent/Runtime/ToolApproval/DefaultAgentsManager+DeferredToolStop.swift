import Foundation

extension DefaultAgentsManager {
    /// Publishes a live Claude approval request produced by `AgentCLIKit` into Alveary's event buffer.
    func handleDeferredToolRequest(_ deferredToolRequest: ClaudeDeferredToolRequest) async {
        let conversationId = deferredToolRequest.conversationId
        guard let managedBuffer = eventBuffers[conversationId] else {
            return
        }
        guard managedBuffer.allowsReplay else {
            return
        }
        guard !closingConversationIds.contains(conversationId) else {
            return
        }
        let services = agentCLIKitServices
        let runtimeConversationId = services.hostAdapter.conversationId(conversationId)
        if let status = await services.runtime.status(conversationId: runtimeConversationId) {
            agentCLIKitStatuses[conversationId] = status
        }
        guard agentCLIKitStatuses[conversationId]?.processIdentifier != nil else {
            return
        }
        let key = ClaudeToolApprovalKey(
            sessionId: deferredToolRequest.request.sessionId,
            toolUseId: deferredToolRequest.request.toolUseId
        )
        // Hook notifications are delayed so preceding tool_use rows can render first. A batch
        // decision may already have answered this sibling hook before its delayed notification arrives.
        guard !managedBuffer.resolvedLiveToolApprovals.contains(key) else {
            return
        }
        let generation = managedBuffer.generation
        guard managedBuffer.acceptsLiveEvents || managedBuffer.hasDeferredToolStop else {
            return
        }
        if managedBuffer.hasDeferredToolStop {
            await handleStreamEvent(
                .toolApprovalRequested(deferredToolRequest.request),
                conversationId: conversationId,
                generation: generation,
                providerId: "claude",
                allowAfterDeferredStop: true
            )
            return
        }

        eventBuffers[conversationId]?.pendingLiveToolApprovals += 1

        await handleStreamEvent(
            .toolApprovalRequested(deferredToolRequest.request),
            conversationId: conversationId,
            generation: generation,
            providerId: "claude",
            allowAfterDeferredStop: true
        )
    }
}

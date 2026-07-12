import Foundation

extension DefaultAgentsManager {
    func spawn(id: String, config: AgentSpawnConfig, forkSession: Bool) async throws {
        try await spawnWithAgentCLIKit(id: id, config: config, forkSession: forkSession)
    }

    func subscribe(conversationId: String, afterIndex: Int = 0) -> AgentEventSubscription? {
        guard let managedBuffer = eventBuffers[conversationId], managedBuffer.allowsReplay else {
            return nil
        }
        let subscription = managedBuffer.buffer.subscribe(afterIndex: afterIndex)
        return AgentEventSubscription(generation: managedBuffer.generation, stream: subscription.stream)
    }

    func retainedEventCount(conversationId: String) -> Int {
        eventBuffers[conversationId]?.buffer.retainedCount ?? 0
    }

    func markPersisted(conversationId: String, generation: UUID, upTo index: Int) {
        let services = agentCLIKitServices
        if let managedBuffer = eventBuffers[conversationId],
           managedBuffer.generation == generation,
           let agentGeneration = agentCLIKitGenerationUUIDs[conversationId]?.first(where: { $0.value == generation })?.key,
           let agentEnvelopeIndex = managedBuffer.agentCLIKitEnvelopeIndex(upToObservedIndex: index) {
            Task {
                await services.runtime.markPersisted(
                    conversationId: services.hostAdapter.conversationId(conversationId),
                    generation: agentGeneration,
                    upTo: agentEnvelopeIndex
                )
            }
        }
        guard let managedBuffer = eventBuffers[conversationId], managedBuffer.generation == generation else {
            return
        }
        managedBuffer.buffer.markPersisted(upTo: index)

        if !hasRuntimePreventingBufferCleanup(conversationId: conversationId),
           !managedBuffer.buffer.hasSubscribers,
           !managedBuffer.buffer.hasUnpersistedEvents {
            scheduleBufferCleanup(for: conversationId, generation: generation, delay: .seconds(30))
        }
    }

    func hasRuntimePreventingBufferCleanup(conversationId: String) -> Bool {
        agentCLIKitStatuses[conversationId]?.isProcessRunning == true ||
            spawningIds.contains(conversationId) ||
            reconfiguringIds.contains(conversationId) ||
            suspendingIds.contains(conversationId)
    }
}

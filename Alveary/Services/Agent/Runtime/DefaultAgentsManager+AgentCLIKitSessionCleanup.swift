import AgentCLIKit
import Foundation

extension DefaultAgentsManager {
    func tearDownAgentCLIKitRuntime(conversationId: String, removeSession: Bool) async {
        guard let services = agentCLIKitServices else {
            return
        }
        let runtimeConversationId = services.hostAdapter.conversationId(conversationId)
        let runtimeStatusProviderId = await services.runtime.status(conversationId: runtimeConversationId)?.providerId
        let activeProviderId = agentCLIKitStatuses[conversationId]?.providerId
            ?? runtimeStatusProviderId
        agentCLIKitEventTasks.removeValue(forKey: conversationId)?.cancel()
        agentCLIKitStatusTasks.removeValue(forKey: conversationId)?.cancel()
        eventBuffers[conversationId]?.allowsReplay = false
        eventBuffers[conversationId]?.acceptsLiveEvents = false
        eventBuffers[conversationId]?.buffer.finishAll()
        await services.liveHookDecisionProvider.discardDecisions(conversationId: conversationId)
        await services.runtime.destroy(conversationId: runtimeConversationId)
        if removeSession {
            do {
                try await removeAgentCLIKitSessionRecord(
                    conversationId: runtimeConversationId,
                    activeProviderId: activeProviderId,
                    services: services
                )
            } catch {
                pendingSessionRemovalErrors[conversationId] = error.localizedDescription
            }
        }
        agentCLIKitStatuses.removeValue(forKey: conversationId)
        agentCLIKitGenerationByConversation.removeValue(forKey: conversationId)
        agentCLIKitGenerationUUIDs.removeValue(forKey: conversationId)
        closingConversationIds.remove(conversationId)
        pendingSessionRemovalIds.remove(conversationId)
        clearStatus(for: conversationId)
    }

    func removeAgentCLIKitSessionRecord(
        conversationId: AgentCLIKit.AgentConversationID,
        activeProviderId: AgentCLIKit.AgentProviderID?,
        services: AgentCLIKitHostServices
    ) async throws {
        if let activeProviderId {
            try await services.sessionStore.remove(
                conversationId: conversationId,
                providerId: activeProviderId
            )
            return
        }

        let providerIds = await services.providerRegistry.allDefinitions().map(\.id)
        for providerId in providerIds {
            try await services.sessionStore.remove(
                conversationId: conversationId,
                providerId: providerId
            )
        }
    }
}

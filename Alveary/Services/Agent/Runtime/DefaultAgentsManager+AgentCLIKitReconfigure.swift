import AgentCLIKit
import Foundation

extension DefaultAgentsManager {
    func reconfigureSessionWithAgentCLIKit(conversationId: String, config: AgentSpawnConfig) async throws {
        guard let services = agentCLIKitServices else {
            return
        }
        await installAgentCLIKitLiveHookHandlerIfNeeded(services: services)
        guard !spawningIds.contains(conversationId) else {
            throw AgentError.spawnFailed("Spawn already in progress for \(conversationId)")
        }
        guard !reconfiguringIds.contains(conversationId) else {
            throw AgentError.spawnFailed("Reconfigure already in progress for \(conversationId)")
        }
        reconfiguringIds.insert(conversationId)
        defer {
            reconfiguringIds.remove(conversationId)
            handleAgentCLIKitDeferredKillAfterSpawn(for: conversationId)
        }

        let runtimeConversationId = services.hostAdapter.conversationId(conversationId)
        let replayCursor = await services.runtime.status(conversationId: runtimeConversationId)?.lastEventIndex
        do {
            prepareAgentCLIKitBufferReplacement(conversationId: conversationId)
            let spawnConfig = try await agentCLIKitSpawnConfig(config, forkSession: true, services: services)
            try await services.runtime.reconfigure(
                conversationId: runtimeConversationId,
                config: spawnConfig
            )
            await refreshAgentCLIKitStatus(conversationId: conversationId, services: services)
            let subscription = await services.runtime.subscribe(
                conversationId: runtimeConversationId,
                afterIndex: replayCursor
            )
            installAgentCLIKitSubscriptionBuffer(
                conversationId: conversationId,
                config: config,
                subscription: subscription,
                dropsPreStartTerminalLifecycle: true
            )
        } catch {
            await restoreAgentCLIKitSubscriptionAfterFailedReplacement(
                conversationId: conversationId,
                config: config,
                runtimeConversationId: runtimeConversationId,
                replayCursor: replayCursor,
                services: services
            )
            updateStatus(.error, for: conversationId)
            await MainActor.run {
                let state = conversationStatesStore.withLock { $0[conversationId] }
                state?.lastTurnError = "Reconfigure failed: \(error.localizedDescription)"
            }
            throw error
        }
    }

    func restoreAgentCLIKitSubscriptionAfterFailedReplacement(
        conversationId: String,
        config: AgentSpawnConfig,
        runtimeConversationId: AgentCLIKit.AgentConversationID,
        replayCursor: Int?,
        services: AgentCLIKitHostServices
    ) async {
        guard await services.runtime.status(conversationId: runtimeConversationId)?.isProcessRunning == true else {
            return
        }
        let subscription = await services.runtime.subscribe(
            conversationId: runtimeConversationId,
            afterIndex: replayCursor
        )
        installAgentCLIKitSubscriptionBuffer(
            conversationId: conversationId,
            config: config,
            subscription: subscription,
            hasImmediateTurn: false
        )
    }
}

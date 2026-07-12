import AgentCLIKit
import Foundation

private struct AgentCLIKitReconfigureFailureContext {
    let conversationId: String
    let config: AgentSpawnConfig
    let runtimeConversationId: AgentCLIKit.AgentConversationID
    let replayCursor: Int?
    let services: AgentCLIKitHostServices
}

extension DefaultAgentsManager {
    @discardableResult
    func reconfigureSessionWithAgentCLIKit(conversationId: String, config: AgentSpawnConfig) async throws -> AgentSessionReconfigureResult {
        let services = agentCLIKitServices
        await installAgentCLIKitLiveHookHandlerIfNeeded(services: services)
        guard !spawningIds.contains(conversationId) else {
            throw AgentError.spawnFailed("Spawn already in progress for \(conversationId)")
        }
        guard !reconfiguringIds.contains(conversationId), !suspendingIds.contains(conversationId) else {
            throw AgentError.spawnFailed("Session change already in progress for \(conversationId)")
        }
        reconfiguringIds.insert(conversationId)
        defer {
            reconfiguringIds.remove(conversationId)
            handleAgentCLIKitDeferredKillAfterSpawn(for: conversationId)
        }

        let runtimeConversationId = services.hostAdapter.conversationId(conversationId)
        let replayCursor = await services.runtime.status(conversationId: runtimeConversationId)?.lastEventIndex
        do {
            let spawnConfig = try await agentCLIKitSpawnConfig(config, forkSession: true, services: services)
            let result = try await services.runtime.reconfigure(
                conversationId: runtimeConversationId,
                config: spawnConfig
            )
            await refreshAgentCLIKitStatus(conversationId: conversationId, services: services)
            guard result == .restarted else {
                return AgentSessionReconfigureResult(result)
            }

            prepareAgentCLIKitBufferReplacement(conversationId: conversationId)
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
            return .restarted
        } catch {
            await handleAgentCLIKitReconfigureFailure(
                error,
                context: AgentCLIKitReconfigureFailureContext(
                    conversationId: conversationId,
                    config: config,
                    runtimeConversationId: runtimeConversationId,
                    replayCursor: replayCursor,
                    services: services
                )
            )
            throw error
        }
    }

    private func handleAgentCLIKitReconfigureFailure(
        _ error: Error,
        context: AgentCLIKitReconfigureFailureContext
    ) async {
        await restoreAgentCLIKitSubscriptionAfterFailedReplacement(
            conversationId: context.conversationId,
            config: context.config,
            runtimeConversationId: context.runtimeConversationId,
            replayCursor: context.replayCursor,
            services: context.services
        )
        updateStatus(.error, for: context.conversationId)
        await MainActor.run {
            let state = conversationStatesStore.withLock { $0[context.conversationId] }
            state?.lastTurnError = "Reconfigure failed: \(error.localizedDescription)"
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

private extension AgentSessionReconfigureResult {
    init(_ result: AgentCLIKit.AgentRuntimeReconfigureResult) {
        switch result {
        case .restarted:
            self = .restarted
        case .appliedInPlace:
            self = .appliedInPlace
        case .nextTurnRequired:
            self = .nextTurnRequired
        }
    }
}

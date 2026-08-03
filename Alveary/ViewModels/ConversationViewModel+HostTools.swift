import Foundation

extension ConversationViewModel {
    func startFreshRuntimeSessionWithHostToolTransition(
        config: AgentSpawnConfig
    ) async throws -> HostToolRuntimeTransition {
        let hostToolTransition = state.beginHostToolRuntimeTransition()
        do {
            await flushPendingSaveIfNeeded()
            try await prepareForSpawn(config: config)
            try await agentsManager.startFreshSession(conversationId: conversation.id, config: config)
            return hostToolTransition
        } catch {
            state.finishHostToolRuntimeTransition(
                hostToolTransition,
                appliedRequestedConfiguration: false
            )
            throw error
        }
    }
}

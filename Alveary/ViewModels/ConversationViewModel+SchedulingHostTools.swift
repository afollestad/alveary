import Foundation

extension ConversationViewModel {
    func startFreshRuntimeSessionWithSchedulingHostToolTransition(
        config: AgentSpawnConfig
    ) async throws -> SchedulingHostToolRuntimeTransition {
        let hostToolTransition = state.beginSchedulingHostToolRuntimeTransition()
        do {
            await flushPendingSaveIfNeeded()
            try await prepareForSpawn(config: config)
            try await agentsManager.startFreshSession(conversationId: conversation.id, config: config)
            return hostToolTransition
        } catch {
            state.finishSchedulingHostToolRuntimeTransition(
                hostToolTransition,
                appliedRequestedConfiguration: false
            )
            throw error
        }
    }
}

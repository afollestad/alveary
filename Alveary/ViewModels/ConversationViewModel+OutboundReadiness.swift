import Foundation

extension ConversationViewModel {
    func prepareRuntimeForOutbound(
        settingsSource: SessionSettingsConfigSource = .nextTurn
    ) async throws {
        guard !needsSetup else {
            return
        }

        switch await agentsManager.outboundReadiness(conversationId: conversation.id) {
        case .ready:
            return
        case .respawnRequired:
            try await startAgentReserved(config: makeSpawnConfig(settingsSource: settingsSource))
            state.respawnAttempts = 0
        case .blocked(let reason):
            throw AgentError.spawnFailed(reason)
        }
    }

    func sendAttemptWithSingleRespawnRecovery(
        _ message: String,
        stagedContextOverride: String?,
        useCurrentStagedContextWhenOverrideNil: Bool,
        existingLocalUserMessageID: String,
        respawnSettingsSource: SessionSettingsConfigSource
    ) async throws {
        do {
            try await sendReserved(
                message,
                stagedContextOverride: stagedContextOverride,
                useCurrentStagedContextWhenOverrideNil: useCurrentStagedContextWhenOverrideNil,
                existingLocalUserMessageID: existingLocalUserMessageID
            )
        } catch AgentError.stdinClosed {
            guard case .respawnRequired = await agentsManager.outboundReadiness(conversationId: conversation.id) else {
                throw AgentError.stdinClosed
            }
            try await startAgentReserved(config: makeSpawnConfig(settingsSource: respawnSettingsSource))
            state.respawnAttempts = 0
            try await sendReserved(
                message,
                stagedContextOverride: stagedContextOverride,
                useCurrentStagedContextWhenOverrideNil: useCurrentStagedContextWhenOverrideNil,
                existingLocalUserMessageID: existingLocalUserMessageID
            )
        }
    }
}

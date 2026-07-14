import Foundation

extension ConversationViewModel {
    @discardableResult
    func prepareRuntimeForOutbound(
        settingsSource: SessionSettingsConfigSource = .nextTurn
    ) async throws -> String? {
        guard !needsSetup else {
            return nil
        }

        if settingsSource == .nextTurn,
           state.liveSessionConfig?.isAutomatedScheduledTurn == true {
            await agentsManager.suspendRuntime(conversationId: conversation.id)
            let recoveryContext = try await respawnRuntimeForOutbound(settingsSource: settingsSource)
            state.respawnAttempts = 0
            return recoveryContext
        }

        switch await agentsManager.outboundReadiness(conversationId: conversation.id) {
        case .ready:
            return nil
        case .respawnRequired:
            let recoveryContext = try await respawnRuntimeForOutbound(settingsSource: settingsSource)
            state.respawnAttempts = 0
            return recoveryContext
        case .blocked(let reason):
            throw AgentError.spawnFailed(reason)
        }
    }

    func respawnRuntimeForOutbound(
        settingsSource: SessionSettingsConfigSource
    ) async throws -> String? {
        let config = try makeSpawnConfig(settingsSource: settingsSource)
        do {
            try await startAgentReserved(config: config)
            return nil
        } catch {
            return try await recoverNonresumableSessionForOutboundIfNeeded(error, config: config)
        }
    }

    func sendAttemptWithSingleRespawnRecovery(
        _ outbound: OutboundMessageText,
        stagedContextOverride: String?,
        useCurrentStagedContextWhenOverrideNil: Bool,
        existingLocalUserMessageID: String,
        respawnSettingsSource: SessionSettingsConfigSource,
        marksSessionHandoffSeedTurn: Bool = false,
        initialGoal: String? = nil,
        onResolvedRecoveryContext: ((SessionRecoveryStagedContext) -> Void)? = nil
    ) async throws {
        do {
            try await sendReserved(
                outbound.visibleText,
                transportText: outbound.transportText,
                initialGoal: initialGoal,
                attachments: outbound.attachments,
                fileAttachments: outbound.consumedFileAttachments,
                appShots: outbound.appShots,
                providerMetadata: outbound.providerMetadata,
                stagedContextOverride: stagedContextOverride,
                useCurrentStagedContextWhenOverrideNil: useCurrentStagedContextWhenOverrideNil,
                existingLocalUserMessageID: existingLocalUserMessageID,
                marksSessionHandoffSeedTurn: marksSessionHandoffSeedTurn
            )
        } catch {
            let recoveryContext = try await recoveryContextAfterSendFailure(
                error,
                respawnSettingsSource: respawnSettingsSource
            )
            let resolvedContext = resolveSessionRecoveryStagedContext(
                recoveryContext: recoveryContext,
                stagedContextOverride: stagedContextOverride,
                useCurrentStagedContextWhenOverrideNil: useCurrentStagedContextWhenOverrideNil
            )
            onResolvedRecoveryContext?(resolvedContext)
            state.respawnAttempts = 0
            try await sendReserved(
                outbound.visibleText,
                transportText: outbound.transportText,
                initialGoal: initialGoal,
                attachments: outbound.attachments,
                fileAttachments: outbound.consumedFileAttachments,
                appShots: outbound.appShots,
                providerMetadata: outbound.providerMetadata,
                stagedContextOverride: resolvedContext.stagedContext,
                useCurrentStagedContextWhenOverrideNil: recoveryContext == nil ? useCurrentStagedContextWhenOverrideNil : false,
                existingLocalUserMessageID: existingLocalUserMessageID,
                marksSessionHandoffSeedTurn: marksSessionHandoffSeedTurn
            )
            if let consumedCurrentStagedContext = resolvedContext.consumedCurrentStagedContext {
                state.stagedContext = nil
                clearConsumedPendingRestoreContext(using: consumedCurrentStagedContext)
            }
        }
    }

    private func recoveryContextAfterSendFailure(
        _ error: Error,
        respawnSettingsSource: SessionSettingsConfigSource
    ) async throws -> String? {
        if isNonresumableProviderSessionError(error) {
            return try await recoverNonresumableSessionForOutboundIfNeeded(
                error,
                config: makeSpawnConfig(settingsSource: respawnSettingsSource)
            )
        }

        guard case AgentError.stdinClosed = error else {
            throw error
        }
        guard case .respawnRequired = await agentsManager.outboundReadiness(conversationId: conversation.id) else {
            throw AgentError.stdinClosed
        }
        return try await respawnRuntimeForOutbound(settingsSource: respawnSettingsSource)
    }
}

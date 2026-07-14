import Foundation

struct OutboundRespawnConfiguration {
    let settingsSource: SessionSettingsConfigSource
    let hostToolExposure: SchedulingHostToolExposure
}

extension ConversationViewModel {
    @discardableResult
    func prepareRuntimeForOutbound(
        settingsSource: SessionSettingsConfigSource = .nextTurn,
        hostToolExposure: SchedulingHostToolExposure = .ordinaryOutbound
    ) async throws -> String? {
        guard !needsSetup else {
            return nil
        }

        if settingsSource == .nextTurn,
           state.liveSessionConfig?.isAutomatedScheduledTurn == true {
            await agentsManager.suspendRuntime(conversationId: conversation.id)
            let recoveryContext = try await respawnRuntimeForOutbound(
                settingsSource: settingsSource,
                hostToolExposure: hostToolExposure
            )
            state.respawnAttempts = 0
            return recoveryContext
        }

        switch await agentsManager.outboundReadiness(conversationId: conversation.id) {
        case .ready:
            if hostToolExposure == .ordinaryOutbound {
                try await reconcileSchedulingHostToolsForOrdinaryOutbound(settingsSource: settingsSource)
            }
            return nil
        case .respawnRequired:
            let recoveryContext = try await respawnRuntimeForOutbound(
                settingsSource: settingsSource,
                hostToolExposure: hostToolExposure
            )
            state.respawnAttempts = 0
            return recoveryContext
        case .blocked(let reason):
            throw AgentError.spawnFailed(reason)
        }
    }

    func respawnRuntimeForOutbound(
        settingsSource: SessionSettingsConfigSource,
        hostToolExposure: SchedulingHostToolExposure = .ordinaryOutbound
    ) async throws -> String? {
        let config = try makeSpawnConfig(
            settingsSource: settingsSource,
            hostToolExposure: hostToolExposure
        )
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
        respawn: OutboundRespawnConfiguration,
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
                respawnSettingsSource: respawn.settingsSource,
                hostToolExposure: respawn.hostToolExposure
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
        respawnSettingsSource: SessionSettingsConfigSource,
        hostToolExposure: SchedulingHostToolExposure
    ) async throws -> String? {
        if isNonresumableProviderSessionError(error) {
            return try await recoverNonresumableSessionForOutboundIfNeeded(
                error,
                config: makeSpawnConfig(
                    settingsSource: respawnSettingsSource,
                    hostToolExposure: hostToolExposure
                )
            )
        }

        guard case AgentError.stdinClosed = error else {
            throw error
        }
        guard case .respawnRequired = await agentsManager.outboundReadiness(conversationId: conversation.id) else {
            throw AgentError.stdinClosed
        }
        return try await respawnRuntimeForOutbound(
            settingsSource: respawnSettingsSource,
            hostToolExposure: hostToolExposure
        )
    }

    private func reconcileSchedulingHostToolsForOrdinaryOutbound(
        settingsSource: SessionSettingsConfigSource
    ) async throws {
        let config = try makeSpawnConfig(
            settingsSource: settingsSource,
            hostToolExposure: .ordinaryOutbound
        )
        let liveConfig = state.liveSessionConfig
        guard state.requiresSchedulingHostToolReplacement
                || liveConfig?.hostToolServer != config.hostToolServer
                || liveConfig?.hostTools != config.hostTools else {
            return
        }

        state.isReconfiguringSession = true
        defer { state.isReconfiguringSession = false }

        let hostToolTransition = state.beginSchedulingHostToolRuntimeTransition()
        do {
            try await prepareForSpawn(config: config)
            let outcome = try await performRuntimeReconfigure(
                config: config,
                hostToolTransition: hostToolTransition
            )
            applyReconfigureResult(outcome, config: config)
        } catch {
            state.finishSchedulingHostToolRuntimeTransition(
                hostToolTransition,
                appliedRequestedConfiguration: false
            )
            throw error
        }
    }
}

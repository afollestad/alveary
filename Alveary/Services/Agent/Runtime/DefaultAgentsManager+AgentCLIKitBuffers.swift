import AgentCLIKit
import Foundation

extension DefaultAgentsManager {
    private func installAgentCLIKitBuffer(
        conversationId: String,
        agentGeneration: Int,
        hasImmediateTurn: Bool,
        initialTurnActivityVisibility: AgentTurnActivityVisibility,
        defersScheduledTerminalNotifications: Bool
    ) -> UUID {
        let generation = UUID()
        eventBuffers[conversationId]?.buffer.finishAll()
        agentCLIKitGenerationByConversation[conversationId] = agentGeneration
        agentCLIKitGenerationUUIDs[conversationId, default: [:]][agentGeneration] = generation
        deniedToolUseIdsByConversation.removeValue(forKey: conversationId)
        cancelledInteractionsByConversation.removeValue(forKey: conversationId)
        let managedBuffer = ManagedEventBuffer(
            generation: generation,
            allowsReplay: true,
            acceptsLiveEvents: true,
            hasDeferredToolStop: false,
            pendingLiveToolApprovals: 0,
            hasSentPendingUserActionNotification: false,
            resolvedLiveToolApprovals: [],
            deferredToolStopSessionId: nil,
            deferredToolStopToolUseId: nil,
            defersScheduledTerminalNotifications: defersScheduledTerminalNotifications,
            buffer: EventBuffer()
        )
        if hasImmediateTurn {
            managedBuffer.currentTurnActivityVisibility = initialTurnActivityVisibility
        }
        eventBuffers[conversationId] = managedBuffer
        Task { @MainActor in
            let state = conversationState(for: conversationId)
            if hasImmediateTurn {
                state.turnState.beginTurn()
            }
        }
        updateStatus(hasImmediateTurn ? .busy : .idle, for: conversationId)
        return generation
    }

    func prepareAgentCLIKitBufferReplacement(conversationId: String) {
        agentCLIKitEventTasks.removeValue(forKey: conversationId)?.cancel()
        cancelledInteractionsByConversation.removeValue(forKey: conversationId)
        eventBuffers[conversationId]?.allowsReplay = false
        eventBuffers[conversationId]?.acceptsLiveEvents = false
        eventBuffers[conversationId]?.buffer.finishAll()
    }

    func installAgentCLIKitSubscriptionBuffer(
        conversationId: String,
        config: AgentSpawnConfig,
        subscription: AgentCLIKit.AgentEventSubscription,
        dropsPreStartTerminalLifecycle: Bool = false,
        hasImmediateTurn: Bool? = nil,
        initialTurnActivityVisibility: AgentTurnActivityVisibility? = nil
    ) {
        let resolvedHasImmediateTurn = hasImmediateTurn ?? !(config.initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let resolvedInitialTurnActivityVisibility = initialTurnActivityVisibility ??
            (resolvedHasImmediateTurn ? .visible : .hidden)
        let bufferGeneration = installAgentCLIKitBuffer(
            conversationId: conversationId,
            agentGeneration: subscription.generation,
            hasImmediateTurn: resolvedHasImmediateTurn,
            initialTurnActivityVisibility: resolvedInitialTurnActivityVisibility,
            defersScheduledTerminalNotifications: config.isAutomatedScheduledTurn
        )
        startAgentCLIKitEventTask(
            conversationId: conversationId,
            subscription: subscription,
            bufferGeneration: bufferGeneration,
            workingDirectory: config.workingDirectory,
            dropsPreStartTerminalLifecycle: dropsPreStartTerminalLifecycle
        )
    }

    private func startAgentCLIKitEventTask(
        conversationId: String,
        subscription: AgentCLIKit.AgentEventSubscription,
        bufferGeneration: UUID,
        workingDirectory: String,
        dropsPreStartTerminalLifecycle: Bool = false
    ) {
        agentCLIKitEventTasks[conversationId]?.cancel()
        agentCLIKitEventTasks[conversationId] = Task { [weak self] in
            var hasSeenRuntimeStart = !dropsPreStartTerminalLifecycle
            for await envelope in subscription.events {
                guard !Task.isCancelled else {
                    return
                }
                // Replacement buffers can replay an old process exit that raced after the cursor; keep real content,
                // but ignore that stale terminal lifecycle until the new runtime start boundary arrives.
                if !hasSeenRuntimeStart {
                    if envelope.isRuntimeStartLifecycle {
                        hasSeenRuntimeStart = true
                    } else if envelope.isTerminalLifecycle {
                        continue
                    }
                }
                await self?.processAgentCLIKitEnvelope(
                    envelope,
                    conversationId: conversationId,
                    subscriptionGeneration: subscription.generation,
                    subscriptionBufferGeneration: bufferGeneration,
                    workingDirectory: workingDirectory
                )
            }
            guard !Task.isCancelled else {
                return
            }
            await self?.finishStreamBufferIfCurrent(conversationId: conversationId, generation: bufferGeneration)
        }
    }

    private func processAgentCLIKitEnvelope(
        _ envelope: AgentCLIKit.AgentEventEnvelope,
        conversationId: String,
        subscriptionGeneration: Int,
        subscriptionBufferGeneration: UUID,
        workingDirectory: String
    ) async {
        guard !Task.isCancelled else {
            return
        }
        let isHostToolServerUnavailableDiagnostic = envelope.isHostToolServerUnavailableDiagnostic
        guard !isHostToolServerUnavailableDiagnostic || envelope.generation >= subscriptionGeneration else {
            return
        }
        await recordProviderSessionBindingIfNeeded(
            from: envelope,
            conversationId: conversationId,
            workingDirectory: workingDirectory
        )
        let generation = agentCLIKitBufferGeneration(
            for: envelope,
            conversationId: conversationId,
            subscriptionGeneration: subscriptionGeneration,
            subscriptionBufferGeneration: subscriptionBufferGeneration
        )
        if isHostToolServerUnavailableDiagnostic {
            guard !Task.isCancelled else {
                return
            }
            await markSchedulingHostToolsUnavailableIfCurrent(
                conversationId: conversationId,
                subscriptionGeneration: subscriptionGeneration,
                envelopeGeneration: envelope.generation,
                bufferGeneration: generation
            )
        }
        for event in AgentCLIKitEventMapper().conversationEvents(from: envelope) {
            await handleStreamEvent(
                event,
                conversationId: conversationId,
                generation: generation,
                providerId: envelope.providerId.rawValue,
                runtimeEventIndex: envelope.index
            )
        }
        recordAgentCLIKitEnvelopeIndex(envelope.index, conversationId: conversationId, generation: generation)
    }

    private func agentCLIKitBufferGeneration(
        for envelope: AgentCLIKit.AgentEventEnvelope,
        conversationId: String,
        subscriptionGeneration: Int,
        subscriptionBufferGeneration: UUID
    ) -> UUID {
        guard envelope.generation != subscriptionGeneration else {
            return subscriptionBufferGeneration
        }
        return currentAgentCLIKitGenerationUUID(
            conversationId: conversationId,
            agentGeneration: envelope.generation
        )
    }

    private func markSchedulingHostToolsUnavailableIfCurrent(
        conversationId: String,
        subscriptionGeneration: Int,
        envelopeGeneration: Int,
        bufferGeneration: UUID
    ) async {
        guard envelopeGeneration >= subscriptionGeneration,
              let managedBuffer = eventBuffers[conversationId],
              managedBuffer.generation == bufferGeneration,
              managedBuffer.acceptsLiveEvents else {
            return
        }
        await markSchedulingHostToolsUnavailable(
            conversationId: conversationId,
            requiresRuntimeReplacement: true
        )
    }

    private func currentAgentCLIKitGenerationUUID(conversationId: String, agentGeneration: Int) -> UUID {
        let defersScheduledTerminalNotifications = eventBuffers[conversationId]?
            .defersScheduledTerminalNotifications ?? false
        if agentCLIKitGenerationByConversation[conversationId] != agentGeneration {
            return installAgentCLIKitBuffer(
                conversationId: conversationId,
                agentGeneration: agentGeneration,
                hasImmediateTurn: false,
                initialTurnActivityVisibility: .hidden,
                defersScheduledTerminalNotifications: defersScheduledTerminalNotifications
            )
        }
        if let existing = agentCLIKitGenerationUUIDs[conversationId]?[agentGeneration] {
            return existing
        }
        return installAgentCLIKitBuffer(
            conversationId: conversationId,
            agentGeneration: agentGeneration,
            hasImmediateTurn: false,
            initialTurnActivityVisibility: .hidden,
            defersScheduledTerminalNotifications: defersScheduledTerminalNotifications
        )
    }
}

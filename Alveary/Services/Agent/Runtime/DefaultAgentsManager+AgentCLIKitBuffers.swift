import AgentCLIKit
import Foundation

extension DefaultAgentsManager {
    private func installAgentCLIKitBuffer(
        conversationId: String,
        agentGeneration: Int,
        hasImmediateTurn: Bool,
        initialTurnActivityVisibility: AgentTurnActivityVisibility
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
            initialTurnActivityVisibility: resolvedInitialTurnActivityVisibility
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
        let mapper = AgentCLIKitEventMapper()
        agentCLIKitEventTasks[conversationId] = Task { [weak self] in
            var hasSeenRuntimeStart = !dropsPreStartTerminalLifecycle
            for await envelope in subscription.events {
                // Replacement buffers can replay an old process exit that raced after the cursor; keep real content,
                // but ignore that stale terminal lifecycle until the new runtime start boundary arrives.
                if !hasSeenRuntimeStart {
                    if envelope.isRuntimeStartLifecycle {
                        hasSeenRuntimeStart = true
                    } else if envelope.isTerminalLifecycle {
                        continue
                    }
                }
                await self?.recordProviderSessionBindingIfNeeded(
                    from: envelope,
                    conversationId: conversationId,
                    workingDirectory: workingDirectory
                )
                let events = mapper.conversationEvents(from: envelope)
                let generation = envelope.generation == subscription.generation
                    ? bufferGeneration
                    : await self?.currentAgentCLIKitGenerationUUID(
                        conversationId: conversationId,
                        agentGeneration: envelope.generation
                    )
                guard let generation else {
                    continue
                }
                for event in events {
                    await self?.handleStreamEvent(
                        event,
                        conversationId: conversationId,
                        generation: generation,
                        providerId: envelope.providerId.rawValue,
                        runtimeEventIndex: envelope.index
                    )
                }
                await self?.recordAgentCLIKitEnvelopeIndex(envelope.index, conversationId: conversationId, generation: generation)
            }
            guard !Task.isCancelled else {
                return
            }
            await self?.finishStreamBufferIfCurrent(conversationId: conversationId, generation: bufferGeneration)
        }
    }

    private func currentAgentCLIKitGenerationUUID(conversationId: String, agentGeneration: Int) -> UUID {
        if agentCLIKitGenerationByConversation[conversationId] != agentGeneration {
            return installAgentCLIKitBuffer(
                conversationId: conversationId,
                agentGeneration: agentGeneration,
                hasImmediateTurn: false,
                initialTurnActivityVisibility: .hidden
            )
        }
        if let existing = agentCLIKitGenerationUUIDs[conversationId]?[agentGeneration] {
            return existing
        }
        return installAgentCLIKitBuffer(
            conversationId: conversationId,
            agentGeneration: agentGeneration,
            hasImmediateTurn: false,
            initialTurnActivityVisibility: .hidden
        )
    }
}

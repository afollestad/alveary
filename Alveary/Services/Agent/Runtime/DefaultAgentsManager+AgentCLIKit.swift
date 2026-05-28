import AgentCLIKit
import Foundation

extension DefaultAgentsManager {
    var usesAgentCLIKitRuntime: Bool {
        agentCLIKitServices != nil
    }

    func spawnWithAgentCLIKit(id: String, config: AgentSpawnConfig, forkSession: Bool) async throws {
        guard let services = agentCLIKitServices else {
            return
        }
        try assertAgentCLIKitSpawnPreflightAllowed(id: id)
        spawningIds.insert(id)
        defer {
            spawningIds.remove(id)
            handleAgentCLIKitDeferredKillAfterSpawn(for: id)
        }

        try await assertNoActiveAgentCLIKitRuntime(id: id, services: services)
        await installAgentCLIKitLiveHookHandlerIfNeeded(services: services)

        let spawnConfig = try await agentCLIKitSpawnConfig(config, forkSession: forkSession, services: services)
        let runtimeConversationId = services.hostAdapter.conversationId(id)
        let replayCursor = await services.runtime.status(conversationId: runtimeConversationId)?.lastEventIndex
        let subscription = await services.runtime.subscribe(
            conversationId: runtimeConversationId,
            afterIndex: replayCursor
        )
        installAgentCLIKitSubscriptionBuffer(conversationId: id, config: config, subscription: subscription)
        startAgentCLIKitStatusTask(conversationId: id, services: services)

        do {
            try await services.runtime.spawn(
                conversationId: runtimeConversationId,
                config: spawnConfig
            )
            await refreshAgentCLIKitStatus(conversationId: id, services: services)
        } catch {
            await tearDownAgentCLIKitRuntime(conversationId: id, removeSession: false)
            throw error
        }
    }

    func sendMessageWithAgentCLIKit(_ message: String, conversationId: String) async throws {
        guard let services = agentCLIKitServices else {
            return
        }
        guard !shutdownRequested.withLock({ $0 }),
              !closingConversationIds.contains(conversationId) else {
            throw AgentError.stdinClosed
        }
        let runtimeConversationId = services.hostAdapter.conversationId(conversationId)
        guard await services.runtime.status(conversationId: runtimeConversationId)?.isProcessRunning == true else {
            throw AgentError.stdinClosed
        }
        do {
            try await services.runtime.send(
                .userMessage(AgentCLIKit.AgentMessageInput(text: message)),
                conversationId: runtimeConversationId
            )
        } catch {
            guard await services.runtime.status(conversationId: runtimeConversationId)?.isProcessRunning == true else {
                throw AgentError.stdinClosed
            }
            throw error
        }
        guard !shutdownRequested.withLock({ $0 }),
              !closingConversationIds.contains(conversationId) else {
            return
        }
        updateStatus(.busy, for: conversationId)
    }

    func cancelTurnWithAgentCLIKit(conversationId: String) {
        guard let services = agentCLIKitServices else {
            return
        }
        Task {
            await services.runtime.cancel(conversationId: services.hostAdapter.conversationId(conversationId))
        }
    }

    func startFreshSessionWithAgentCLIKit(conversationId: String, config: AgentSpawnConfig) async throws {
        guard let services = agentCLIKitServices else {
            return
        }
        await installAgentCLIKitLiveHookHandlerIfNeeded(services: services)
        guard !spawningIds.contains(conversationId) else {
            throw AgentError.spawnFailed("Spawn already in progress for \(conversationId)")
        }
        guard !reconfiguringIds.contains(conversationId) else {
            throw AgentError.spawnFailed("Session refresh already in progress for \(conversationId)")
        }
        reconfiguringIds.insert(conversationId)
        defer {
            reconfiguringIds.remove(conversationId)
            handleAgentCLIKitDeferredKillAfterSpawn(for: conversationId)
        }

        let runtimeConversationId = services.hostAdapter.conversationId(conversationId)
        let replayCursor = await services.runtime.status(conversationId: runtimeConversationId)?.lastEventIndex
        let previousSessionRecord = try await previousAgentCLIKitSessionRecord(
            conversationId: runtimeConversationId,
            providerId: config.providerId,
            services: services
        )

        do {
            try await replaceWithFreshAgentCLIKitSession(
                conversationId: conversationId,
                config: config,
                runtimeConversationId: runtimeConversationId,
                previousSessionRecord: previousSessionRecord,
                services: services
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
                state?.lastTurnError = "Session handoff failed: \(error.localizedDescription)"
            }
            throw error
        }
    }

    func replaceWithFreshAgentCLIKitSession(
        conversationId: String,
        config: AgentSpawnConfig,
        runtimeConversationId: AgentCLIKit.AgentConversationID,
        previousSessionRecord: AgentCLIKit.AgentSessionRecord?,
        services: AgentCLIKitHostServices
    ) async throws {
        prepareAgentCLIKitBufferReplacement(conversationId: conversationId)
        let spawnConfig = try await agentCLIKitSpawnConfig(config, forkSession: false, services: services)
        try await services.runtime.freshSession(
            conversationId: runtimeConversationId,
            config: spawnConfig
        )
        await refreshAgentCLIKitStatus(conversationId: conversationId, services: services)
        await removePreviousAgentCLIKitSessionState(
            previousSessionRecord,
            services: services
        )
        let subscription = await services.runtime.subscribe(
            conversationId: runtimeConversationId,
            afterIndex: nil
        )
        installAgentCLIKitSubscriptionBuffer(
            conversationId: conversationId,
            config: config,
            subscription: subscription
        )
    }

    func killWithAgentCLIKit(conversationId: String) {
        guard let services = agentCLIKitServices else {
            return
        }
        closingConversationIds.insert(conversationId)
        pendingSessionRemovalIds.insert(conversationId)
        deniedToolUseIdsByConversation.removeValue(forKey: conversationId)
        _ = conversationStatesStore.withLock { $0.removeValue(forKey: conversationId) }
        clearStatus(for: conversationId)
        eventBuffers[conversationId]?.allowsReplay = false
        eventBuffers[conversationId]?.acceptsLiveEvents = false
        eventBuffers[conversationId]?.buffer.finishAll()

        if spawningIds.contains(conversationId) || reconfiguringIds.contains(conversationId) {
            pendingKillIds.insert(conversationId)
            return
        }

        Task {
            await services.runtime.kill(conversationId: services.hostAdapter.conversationId(conversationId))
            await tearDownAgentCLIKitRuntime(conversationId: conversationId, removeSession: true)
        }
    }

    func destroyRuntimeWithAgentCLIKit(conversationId: String, timeout: Duration) async throws {
        if !closingConversationIds.contains(conversationId) {
            killWithAgentCLIKit(conversationId: conversationId)
        }

        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if let removalError = pendingSessionRemovalErrors.removeValue(forKey: conversationId) {
                throw AgentError.spawnFailed(
                    "Destructive teardown cleanup failed for \(conversationId): \(removalError)"
                )
            }
            if agentCLIKitStatuses[conversationId] == nil,
               !closingConversationIds.contains(conversationId),
               !pendingSessionRemovalIds.contains(conversationId),
               !spawningIds.contains(conversationId),
               !reconfiguringIds.contains(conversationId) {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw AgentError.spawnFailed("Timed out waiting for destructive teardown for \(conversationId)")
    }

    func killAllWithAgentCLIKit() {
        let ids = Set(agentCLIKitStatuses.keys)
            .union(spawningIds)
            .union(reconfiguringIds)
        for id in ids {
            killWithAgentCLIKit(conversationId: id)
        }
    }

    private func assertAgentCLIKitSpawnPreflightAllowed(id: String) throws {
        guard !shutdownRequested.withLock({ $0 }) else {
            throw AgentError.spawnFailed("App is shutting down")
        }
        guard !closingConversationIds.contains(id) else {
            throw AgentError.spawnFailed("Conversation is closing")
        }
        guard !spawningIds.contains(id) else {
            throw AgentError.spawnFailed("Spawn already in progress for \(id)")
        }
        guard !reconfiguringIds.contains(id) else {
            throw AgentError.spawnFailed("Reconfigure already in progress for \(id)")
        }
    }

    private func assertNoActiveAgentCLIKitRuntime(id: String, services: AgentCLIKitHostServices) async throws {
        let runtimeStatus = await services.runtime.status(conversationId: services.hostAdapter.conversationId(id))
        if let runtimeStatus {
            agentCLIKitStatuses[id] = runtimeStatus
        }
        guard agentCLIKitStatuses[id]?.isProcessRunning != true,
              runtimeStatus?.isProcessRunning != true else {
            throw AgentError.spawnFailed("Agent already running for \(id). Use reconfigureSession() or kill() before spawning again")
        }
    }

    func refreshAgentCLIKitStatus(conversationId: String, services: AgentCLIKitHostServices) async {
        guard let status = await services.runtime.status(conversationId: services.hostAdapter.conversationId(conversationId)) else {
            return
        }
        applyAgentCLIKitStatus(status, conversationId: conversationId)
    }

    func installAgentCLIKitLiveHookHandlerIfNeeded(services: AgentCLIKitHostServices) async {
        guard !hasInstalledAgentCLIKitLiveHookHandler else {
            return
        }
        hasInstalledAgentCLIKitLiveHookHandler = true
        await services.liveHookDecisionProvider.setDeferredToolRequestHandler { [weak self] request in
            await self?.handleDeferredToolRequestFromHookServer(request)
        }
    }

    func agentCLIKitSpawnConfig(
        _ config: AgentSpawnConfig,
        forkSession: Bool,
        services: AgentCLIKitHostServices
    ) async throws -> AgentCLIKit.AgentSpawnConfig {
        let customConfig = await settingsService.current.providerConfigs[config.providerId]
        if await providerDetection.resolvedPath(for: config.providerId) == nil {
            await providerDetection.checkProvider(config.providerId)
        }
        guard let detectedPath = await providerDetection.resolvedPath(for: config.providerId) else {
            throw AgentError.cliNotInstalled(config.providerId)
        }

        let arguments = try parseExtraArgs(customConfig?.extraArgs ?? "")
        return try services.hostAdapter.spawnConfig(
            from: config,
            arguments: arguments,
            environment: agentCLIKitEnvironment(detectedPath: detectedPath),
            forkSession: forkSession
        )
    }

    private func agentCLIKitEnvironment(detectedPath: String) -> [String: String] {
        var environment = environmentBuilder.buildEnvironment(providerEnv: nil)
        let executableDirectory = URL(fileURLWithPath: detectedPath).deletingLastPathComponent().path
        let existingPath = environment["PATH"] ?? ""
        let pathComponents = existingPath.split(separator: ":").map(String.init)
        if !pathComponents.contains(executableDirectory) {
            environment["PATH"] = ([executableDirectory] + pathComponents).joined(separator: ":")
        }
        return environment
    }

    private func installAgentCLIKitBuffer(
        conversationId: String,
        agentGeneration: Int,
        hasImmediateTurn: Bool
    ) -> UUID {
        let generation = UUID()
        eventBuffers[conversationId]?.buffer.finishAll()
        agentCLIKitGenerationByConversation[conversationId] = agentGeneration
        agentCLIKitGenerationUUIDs[conversationId, default: [:]][agentGeneration] = generation
        deniedToolUseIdsByConversation.removeValue(forKey: conversationId)
        eventBuffers[conversationId] = ManagedEventBuffer(
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
        eventBuffers[conversationId]?.allowsReplay = false
        eventBuffers[conversationId]?.acceptsLiveEvents = false
        eventBuffers[conversationId]?.buffer.finishAll()
    }

    func installAgentCLIKitSubscriptionBuffer(
        conversationId: String,
        config: AgentSpawnConfig,
        subscription: AgentCLIKit.AgentEventSubscription,
        dropsPreStartTerminalLifecycle: Bool = false,
        hasImmediateTurn: Bool? = nil
    ) {
        let bufferGeneration = installAgentCLIKitBuffer(
            conversationId: conversationId,
            agentGeneration: subscription.generation,
            hasImmediateTurn: hasImmediateTurn ?? !(config.initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        )
        startAgentCLIKitEventTask(
            conversationId: conversationId,
            subscription: subscription,
            bufferGeneration: bufferGeneration,
            dropsPreStartTerminalLifecycle: dropsPreStartTerminalLifecycle
        )
    }

    private func startAgentCLIKitEventTask(
        conversationId: String,
        subscription: AgentCLIKit.AgentEventSubscription,
        bufferGeneration: UUID,
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
                        providerId: envelope.providerId.rawValue
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

    private func startAgentCLIKitStatusTask(conversationId: String, services: AgentCLIKitHostServices) {
        agentCLIKitStatusTasks[conversationId]?.cancel()
        agentCLIKitStatusTasks[conversationId] = Task { [weak self] in
            let statuses = await services.runtime.statusUpdates(
                conversationId: services.hostAdapter.conversationId(conversationId)
            )
            for await status in statuses {
                await self?.applyAgentCLIKitStatus(status, conversationId: conversationId)
            }
        }
    }

    private func currentAgentCLIKitGenerationUUID(conversationId: String, agentGeneration: Int) -> UUID {
        if agentCLIKitGenerationByConversation[conversationId] != agentGeneration {
            return installAgentCLIKitBuffer(
                conversationId: conversationId,
                agentGeneration: agentGeneration,
                hasImmediateTurn: false
            )
        }
        if let existing = agentCLIKitGenerationUUIDs[conversationId]?[agentGeneration] {
            return existing
        }
        return installAgentCLIKitBuffer(
            conversationId: conversationId,
            agentGeneration: agentGeneration,
            hasImmediateTurn: false
        )
    }

    private func applyAgentCLIKitStatus(_ status: AgentCLIKit.AgentRuntimeStatus, conversationId: String) {
        agentCLIKitStatuses[conversationId] = status
        processSnapshot.withLock { $0 = [] }
        publishManagedProcessesChanged()
        switch status.waitingState {
        case .approval, .prompt, .planModeExit:
            updateStatus(.waitingForUser, for: conversationId)
        case .idle:
            switch status.state {
            case .starting, .running:
                // A live AgentCLIKit process may simply be waiting for stdin; Alveary marks busy from turn starts instead.
                break
            case .exited, .cancelled:
                if eventBuffers[conversationId]?.hasDeferredToolStop == true,
                   self.status(for: conversationId) == .waitingForUser {
                    return
                }
                updateStatus(.idle, for: conversationId)
            case .failed:
                updateStatus(.error, for: conversationId)
            }
        }
    }

    func handleAgentCLIKitDeferredKillAfterSpawn(for conversationId: String) {
        guard pendingKillIds.remove(conversationId) != nil else {
            return
        }
        Task {
            await tearDownAgentCLIKitRuntime(conversationId: conversationId, removeSession: true)
        }
    }

    private func tearDownAgentCLIKitRuntime(conversationId: String, removeSession: Bool) async {
        guard let services = agentCLIKitServices else {
            return
        }
        agentCLIKitEventTasks.removeValue(forKey: conversationId)?.cancel()
        agentCLIKitStatusTasks.removeValue(forKey: conversationId)?.cancel()
        eventBuffers[conversationId]?.allowsReplay = false
        eventBuffers[conversationId]?.acceptsLiveEvents = false
        eventBuffers[conversationId]?.buffer.finishAll()
        await services.liveHookDecisionProvider.discardDecisions(conversationId: conversationId)
        await services.runtime.destroy(conversationId: services.hostAdapter.conversationId(conversationId))
        if removeSession {
            do {
                if let providerId = services.hostAdapter.providerId("claude") {
                    try await services.sessionStore.remove(
                        conversationId: services.hostAdapter.conversationId(conversationId),
                        providerId: providerId
                    )
                }
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
}

import AgentCLIKit
import Foundation

extension DefaultAgentsManager {
    func spawnWithAgentCLIKit(
        id: String,
        config: AgentSpawnConfig,
        forkSession: Bool,
        initialTurnActivityVisibility: AgentTurnActivityVisibility? = nil,
        dropsPreStartTerminalLifecycle: Bool = false
    ) async throws {
        let services = agentCLIKitServices
        try assertAgentCLIKitSpawnPreflightAllowed(id: id)
        spawningIds.insert(id)
        defer {
            spawningIds.remove(id)
            handleAgentCLIKitDeferredKillAfterSpawn(for: id)
        }

        try await assertNoActiveAgentCLIKitRuntime(id: id, services: services)
        await installAgentCLIKitLiveHookHandlerIfNeeded(services: services)

        let runtimeConversationId = services.hostAdapter.conversationId(id)
        let replayCursor = await services.runtime.status(conversationId: runtimeConversationId)?.lastEventIndex
        let subscription = await services.runtime.subscribe(
            conversationId: runtimeConversationId,
            afterIndex: replayCursor
        )
        installAgentCLIKitSubscriptionBuffer(
            conversationId: id,
            config: config,
            subscription: subscription,
            dropsPreStartTerminalLifecycle: dropsPreStartTerminalLifecycle,
            initialTurnActivityVisibility: initialTurnActivityVisibility
        )
        startAgentCLIKitStatusTask(conversationId: id, services: services)

        do {
            try await spawnAgentCLIKitWithSchedulingHostToolFallback(
                conversationId: id,
                runtimeConversationId: runtimeConversationId,
                config: config,
                forkSession: forkSession,
                services: services
            )
            await refreshAgentCLIKitStatus(conversationId: id, services: services)
        } catch {
            await tearDownAgentCLIKitRuntime(conversationId: id, removeSession: false)
            throw error
        }
    }

    func sendMessageWithAgentCLIKit(
        _ message: String,
        conversationId: String,
        activityVisibility: AgentTurnActivityVisibility,
        attachments: [LocalImageAttachment] = [],
        metadata: [String: AgentCLIKit.JSONValue] = [:]
    ) async throws {
        let services = agentCLIKitServices
        guard !shutdownRequested.withLock({ $0 }),
              !closingConversationIds.contains(conversationId),
              !suspendingIds.contains(conversationId) else {
            throw AgentError.stdinClosed
        }
        let runtimeConversationId = services.hostAdapter.conversationId(conversationId)
        guard let status = await services.runtime.status(conversationId: runtimeConversationId),
              !status.isTerminal,
              status.isProcessRunning else {
            throw AgentError.stdinClosed
        }
        cancelledInteractionsByConversation.removeValue(forKey: conversationId)
        markCurrentTurnActivityVisibility(activityVisibility, conversationId: conversationId)
        do {
            try await services.runtime.send(
                .userMessage(AgentCLIKit.AgentMessageInput(
                    text: message,
                    attachments: attachments.map(AgentCLIKit.AgentInputAttachment.init(localImageAttachment:)),
                    metadata: metadata
                )),
                conversationId: runtimeConversationId
            )
        } catch {
            guard let status = await services.runtime.status(conversationId: runtimeConversationId),
                  !status.isTerminal,
                  status.isProcessRunning else {
                throw AgentError.stdinClosed
            }
            throw error
        }
        if activityVisibility == .visible {
            await threadActivityRecorder.recordVisibleOutbound(conversationId: conversationId)
        }
        guard !shutdownRequested.withLock({ $0 }),
              !closingConversationIds.contains(conversationId) else {
            return
        }
        updateStatus(.busy, for: conversationId)
    }

    func sendGoalStartMessageWithAgentCLIKit(_ request: AgentGoalStartMessageRequest) async throws {
        try await sendMessageWithAgentCLIKit(
            request.message,
            conversationId: request.conversationId,
            activityVisibility: request.activityVisibility,
            attachments: request.attachments,
            metadata: request.metadata.merging([
                AgentCLIKit.AgentGoalMetadata.isInitialGoalTransport: .bool(true),
                AgentCLIKit.AgentGoalMetadata.objective: .string(request.initialGoal)
            ]) { _, new in new }
        )
    }

    func startGoalWithAgentCLIKit(_ objective: String, conversationId: String) async throws {
        let services = agentCLIKitServices
        guard !shutdownRequested.withLock({ $0 }),
              !closingConversationIds.contains(conversationId),
              !suspendingIds.contains(conversationId) else {
            throw AgentError.stdinClosed
        }
        let runtimeConversationId = services.hostAdapter.conversationId(conversationId)
        guard let status = await services.runtime.status(conversationId: runtimeConversationId),
              !status.isTerminal,
              status.isProcessRunning else {
            throw AgentError.stdinClosed
        }
        try await services.runtime.startGoal(objective, conversationId: runtimeConversationId)
        await refreshAgentCLIKitStatus(conversationId: conversationId, services: services)
    }

    func cancelTurnWithAgentCLIKit(conversationId: String) {
        let services = agentCLIKitServices
        Task {
            await services.runtime.cancel(conversationId: services.hostAdapter.conversationId(conversationId))
        }
    }

    /// Drops a host-superseded deferred interaction without deleting its resumable provider session.
    func discardInactiveDeferredInteractionRuntimeWithAgentCLIKit(conversationId: String) async {
        await tearDownAgentCLIKitRuntime(conversationId: conversationId, removeSession: false)
    }

    func performGoalActionWithAgentCLIKit(_ action: AgentCLIKit.AgentGoalAction, conversationId: String) async throws {
        let services = agentCLIKitServices
        try await services.runtime.performGoalAction(
            action,
            conversationId: services.hostAdapter.conversationId(conversationId)
        )
        await refreshAgentCLIKitStatus(conversationId: conversationId, services: services)
    }

    func startFreshSessionWithAgentCLIKit(conversationId: String, config: AgentSpawnConfig) async throws {
        let services = agentCLIKitServices
        await installAgentCLIKitLiveHookHandlerIfNeeded(services: services)
        guard !spawningIds.contains(conversationId) else {
            throw AgentError.spawnFailed("Spawn already in progress for \(conversationId)")
        }
        guard !reconfiguringIds.contains(conversationId),
              !suspendingIds.contains(conversationId) else {
            throw AgentError.spawnFailed("Session change already in progress for \(conversationId)")
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
        let effectiveConfig = try await freshAgentCLIKitSessionWithSchedulingHostToolFallback(
            conversationId: conversationId,
            runtimeConversationId: runtimeConversationId,
            config: config,
            services: services
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
            config: effectiveConfig,
            subscription: subscription
        )
    }

    func killWithAgentCLIKit(conversationId: String, removesConversationState: Bool = true) {
        let services = agentCLIKitServices
        closingConversationIds.insert(conversationId)
        pendingSessionRemovalIds.insert(conversationId)
        deniedToolUseIdsByConversation.removeValue(forKey: conversationId)
        cancelledInteractionsByConversation.removeValue(forKey: conversationId)
        if removesConversationState {
            _ = conversationStatesStore.withLock { $0.removeValue(forKey: conversationId) }
        }
        clearStatus(for: conversationId)
        eventBuffers[conversationId]?.allowsReplay = false
        eventBuffers[conversationId]?.acceptsLiveEvents = false
        eventBuffers[conversationId]?.buffer.finishAll()

        if spawningIds.contains(conversationId) ||
            reconfiguringIds.contains(conversationId) ||
            suspendingIds.contains(conversationId) {
            pendingKillIds.insert(conversationId)
            return
        }

        Task {
            await services.runtime.kill(conversationId: services.hostAdapter.conversationId(conversationId))
            await tearDownAgentCLIKitRuntime(conversationId: conversationId, removeSession: true)
        }
    }

    func destroyRuntimeWithAgentCLIKit(
        conversationId: String,
        timeout: Duration,
        removesConversationState: Bool = true
    ) async throws {
        if !closingConversationIds.contains(conversationId) {
            killWithAgentCLIKit(
                conversationId: conversationId,
                removesConversationState: removesConversationState
            )
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
               !reconfiguringIds.contains(conversationId),
               !suspendingIds.contains(conversationId) {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw AgentError.spawnFailed("Timed out waiting for destructive teardown for \(conversationId)")
    }

    func suspendRuntimeWithAgentCLIKit(conversationId: String) async {
        guard !shutdownRequested.withLock({ $0 }),
              !closingConversationIds.contains(conversationId),
              !spawningIds.contains(conversationId),
              !reconfiguringIds.contains(conversationId),
              !suspendingIds.contains(conversationId) else {
            return
        }

        suspendingIds.insert(conversationId)
        defer {
            suspendingIds.remove(conversationId)
            if let generation = eventBuffers[conversationId]?.generation {
                scheduleBufferCleanup(for: conversationId, generation: generation, delay: .seconds(30))
            }
            handleAgentCLIKitDeferredKillAfterSpawn(for: conversationId)
        }

        let services = agentCLIKitServices
        let runtimeConversationId = services.hostAdapter.conversationId(conversationId)
        guard let status = await services.runtime.status(conversationId: runtimeConversationId) else {
            agentCLIKitStatuses.removeValue(forKey: conversationId)
            return
        }
        agentCLIKitStatuses[conversationId] = status

        guard status.waitingState == .idle,
              !status.isTurnActive else {
            return
        }

        await tearDownAgentCLIKitRuntime(conversationId: conversationId, removeSession: false)
    }

    func killAllWithAgentCLIKit() {
        let ids = Set(agentCLIKitStatuses.keys)
            .union(spawningIds)
            .union(reconfiguringIds)
            .union(suspendingIds)
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
        guard !suspendingIds.contains(id) else {
            throw AgentError.spawnFailed("Runtime suspension already in progress for \(id)")
        }
    }

    private func assertNoActiveAgentCLIKitRuntime(id: String, services: AgentCLIKitHostServices) async throws {
        let runtimeStatus = await services.runtime.status(conversationId: services.hostAdapter.conversationId(id))
        if let runtimeStatus {
            agentCLIKitStatuses[id] = runtimeStatus
        }
        guard agentCLIKitStatuses[id]?.isActiveRuntimePreventingReplacement != true,
              runtimeStatus?.isActiveRuntimePreventingReplacement != true else {
            throw AgentError.spawnFailed("Agent already running for \(id). Use reconfigureSession() or kill() before spawning again")
        }
    }

    func installAgentCLIKitLiveHookHandlerIfNeeded(services: AgentCLIKitHostServices) async {
        guard !hasInstalledAgentCLIKitLiveHookHandler else {
            return
        }
        hasInstalledAgentCLIKitLiveHookHandler = true
        await services.liveHookDecisionProvider.setDeferredToolRequestHandler { [weak self] request in
            await self?.handleDeferredToolRequest(request)
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

        let configuredArguments = try mergedArguments(
            providerId: config.providerId,
            customArguments: parseExtraArgs(customConfig?.extraArgs ?? ""),
            allowedDirectories: config.allowedDirectories
        )
        let arguments = ClaudeNativeSchedulingLaunchPolicy.arguments(
            providerID: config.providerId,
            configuredArguments: configuredArguments
        )
        let environment = ClaudeNativeSchedulingLaunchPolicy.environment(
            providerID: config.providerId,
            baseEnvironment: agentCLIKitEnvironment(detectedPath: detectedPath)
        )
        return try services.hostAdapter.spawnConfig(
            from: config,
            arguments: arguments,
            environment: environment,
            forkSession: forkSession
        )
    }

    private func mergedArguments(
        providerId: String,
        customArguments: [String],
        allowedDirectories: [String]
    ) -> [String] {
        guard providerId == "claude", !allowedDirectories.isEmpty else {
            return customArguments
        }

        var arguments = customArguments
        let existingAddDirs = existingClaudeAddDirectories(in: customArguments)
        for directory in allowedDirectories where !existingAddDirs.contains(CanonicalPath.normalize(directory)) {
            arguments.append("--add-dir")
            arguments.append(directory)
        }
        return arguments
    }

    private func existingClaudeAddDirectories(in arguments: [String]) -> Set<String> {
        var directories = Set<String>()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--add-dir", index + 1 < arguments.count {
                directories.insert(CanonicalPath.normalize(arguments[index + 1]))
                index += 2
                continue
            }
            if argument.hasPrefix("--add-dir=") {
                let value = String(argument.dropFirst("--add-dir=".count))
                directories.insert(CanonicalPath.normalize(value))
            }
            index += 1
        }
        return directories
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

}

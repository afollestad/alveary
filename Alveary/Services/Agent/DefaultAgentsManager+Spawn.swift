import Darwin
import Foundation

extension DefaultAgentsManager {
    func spawn(id: String, config: AgentSpawnConfig, forkSession: Bool) async throws {
        try await spawnImpl(id: id, config: config, forkSession: forkSession, allowReconfigureInFlight: false)
    }

    func subscribe(conversationId: String, afterIndex: Int = 0) -> AgentEventSubscription? {
        guard let managedBuffer = eventBuffers[conversationId], managedBuffer.allowsReplay else {
            return nil
        }

        let subscription = managedBuffer.buffer.subscribe(afterIndex: afterIndex)
        return AgentEventSubscription(generation: managedBuffer.generation, stream: subscription.stream)
    }

    func retainedEventCount(conversationId: String) -> Int {
        eventBuffers[conversationId]?.buffer.retainedCount ?? 0
    }

    func markPersisted(conversationId: String, generation: UUID, upTo index: Int) {
        guard let managedBuffer = eventBuffers[conversationId], managedBuffer.generation == generation else {
            return
        }

        managedBuffer.buffer.markPersisted(upTo: index)

        if processes[conversationId] == nil,
           !managedBuffer.buffer.hasSubscribers,
           !managedBuffer.buffer.hasUnpersistedEvents {
            scheduleBufferCleanup(for: conversationId, generation: generation, delay: .seconds(30))
        }
    }

    private func finishUnpublishedSpawnCancellation(
        launched: LaunchedProcess,
        graceSeconds: TimeInterval = 5
    ) async {
        launched.process.terminate()

        let deadline = Date().addingTimeInterval(graceSeconds)
        while launched.process.isRunning, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }

        if launched.process.isRunning {
            Darwin.kill(launched.process.processIdentifier, SIGKILL)
            while launched.process.isRunning {
                try? await Task.sleep(for: .milliseconds(20))
            }
        }

        launched.closeAllHandles()
    }

    func spawnImpl(
        id: String,
        config: AgentSpawnConfig,
        forkSession: Bool,
        allowReconfigureInFlight: Bool
    ) async throws {
        try assertSpawnAllowed(id: id, allowReconfigureInFlight: allowReconfigureInFlight)

        spawningIds.insert(id)
        defer {
            spawningIds.remove(id)
            handleDeferredKillAfterSpawn(for: id)
        }

        let prepared = try await prepareSpawnContext(id: id, config: config, forkSession: forkSession)
        let launched = try await launchProcess(id: id, config: config, prepared: prepared)
        try await ensureUnpublishedLaunchStillAllowed(id: id, launched: launched)
        let runtime = try await publishRuntime(id: id, config: config, prepared: prepared, launched: launched)
        try await sendInitialPromptIfNeeded(id: id, config: config, prepared: prepared, runtime: runtime)
    }

    private func assertSpawnAllowed(id: String, allowReconfigureInFlight: Bool) throws {
        guard !shutdownRequested.withLock({ $0 }) else {
            throw AgentError.spawnFailed("App is shutting down")
        }
        guard !closingConversationIds.contains(id) else {
            throw AgentError.spawnFailed("Conversation is closing")
        }
        guard !spawningIds.contains(id) else {
            throw AgentError.spawnFailed("Spawn already in progress for \(id)")
        }
        guard allowReconfigureInFlight || !reconfiguringIds.contains(id) else {
            throw AgentError.spawnFailed("Reconfigure already in progress for \(id)")
        }
        if let existing = processes[id], existing.isRunning {
            throw AgentError.spawnFailed("Agent already running for \(id). Use reconfigureSession() or kill() before spawning again")
        }
    }

    private func handleDeferredKillAfterSpawn(for id: String) {
        guard pendingKillIds.remove(id) != nil else {
            return
        }

        let hasPublishedProcess = processes[id] != nil
        suppressExitStatus(for: id, pid: processes[id]?.processIdentifier)
        eventBuffers[id]?.allowsReplay = false
        if hasPublishedProcess {
            Task {
                await teardownProcess(for: id, awaitExit: true, preserveBufferForDurabilityGrace: true)
            }
            _ = conversationStatesStore.withLock { $0.removeValue(forKey: id) }
            clearStatus(for: id)
            return
        }

        _ = conversationStatesStore.withLock { $0.removeValue(forKey: id) }
        clearStatus(for: id)
        closingConversationIds.remove(id)
        if pendingSessionRemovalIds.contains(id) {
            Task {
                await finalizeSessionRemoval(for: id)
            }
        }
    }

    private func prepareSpawnContext(
        id: String,
        config: AgentSpawnConfig,
        forkSession: Bool
    ) async throws -> PreparedSpawnContext {
        let customConfig = await settingsService.current.providerConfigs[config.providerId]
        let cliPath = try await resolveCLIPath(providerId: config.providerId, customConfig: customConfig)
        let adapter = resolveAdapter(for: config.providerId)
        let sessionCwd = CanonicalPath.normalize(config.workingDirectory)
        let isResuming = await sessionManager.createEntry(
            conversationId: id,
            cwd: sessionCwd,
            providerId: config.providerId
        )
        let sessionID = await sessionManager.sessionId(for: id)

        let agentConfig = AgentConfig(
            providerId: config.providerId,
            sessionId: sessionID,
            workingDirectory: config.workingDirectory,
            permissionMode: config.permissionMode,
            model: config.model,
            effort: config.effort,
            initialPrompt: config.initialPrompt
        )

        var arguments = adapter.buildArgs(config: agentConfig)
        let sessionLaunch = adapter.sessionLaunch(
            sessionId: sessionID,
            cwd: sessionCwd,
            isResuming: isResuming,
            forkSession: forkSession
        )
        arguments += sessionLaunch.args
        if let extraArgs = customConfig?.extraArgs, !extraArgs.isEmpty {
            arguments += try parseExtraArgs(extraArgs)
        }

        var providerEnv = adapter.envOverrides(config: agentConfig)
        if let customEnv = customConfig?.env {
            providerEnv.merge(customEnv) { _, custom in custom }
        }

        return PreparedSpawnContext(
            cliPath: cliPath,
            adapter: adapter,
            customConfig: customConfig,
            isResuming: isResuming,
            sessionLaunch: sessionLaunch,
            arguments: arguments,
            environment: environmentBuilder.buildEnvironment(providerEnv: providerEnv)
        )
    }

    private func resolveCLIPath(providerId: String, customConfig: ProviderCustomConfig?) async throws -> String {
        if let customCLI = customConfig?.cli, !customCLI.isEmpty, customCLI.contains("/") {
            return customCLI
        }

        if await providerDetection.resolvedPath(for: providerId) == nil ||
            !(customConfig?.cli?.isEmpty ?? true) {
            await providerDetection.checkProvider(providerId)
        }

        guard let detectedPath = await providerDetection.resolvedPath(for: providerId) else {
            throw AgentError.cliNotInstalled(providerId)
        }
        return detectedPath
    }

    private func launchProcess(
        id: String,
        config: AgentSpawnConfig,
        prepared: PreparedSpawnContext
    ) async throws -> LaunchedProcess {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: prepared.cliPath)
        process.arguments = prepared.arguments
        process.currentDirectoryURL = URL(fileURLWithPath: config.workingDirectory)
        process.environment = prepared.environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        let launched = LaunchedProcess(process: process, stdin: stdin, stdout: stdout, stderr: stderr)
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            launched.closeParentLaunchHandles()
            return launched
        } catch {
            let spawnFailure = error.localizedDescription
            launched.closeAllHandles()

            var sessionCleanupFailure: String?
            if !prepared.isResuming {
                do {
                    try await sessionManager.removeEntry(for: id)
                } catch {
                    sessionCleanupFailure = error.localizedDescription
                }
            }
            await providerDetection.checkProvider(config.providerId)

            if let sessionCleanupFailure {
                throw AgentError.spawnFailed(
                    "Spawn failed: \(spawnFailure). Session cleanup also failed: \(sessionCleanupFailure)"
                )
            }
            throw AgentError.spawnFailed(spawnFailure)
        }
    }

    private func ensureUnpublishedLaunchStillAllowed(id: String, launched: LaunchedProcess) async throws {
        if pendingKillIds.contains(id) || closingConversationIds.contains(id) {
            await finishUnpublishedSpawnCancellation(
                launched: launched
            )
            throw AgentError.spawnFailed("Conversation was closed during spawn")
        }

        if shutdownRequested.withLock({ $0 }) {
            await finishUnpublishedSpawnCancellation(
                launched: launched,
                graceSeconds: 1.0
            )
            throw AgentError.spawnFailed("App is shutting down")
        }
    }

    private func publishRuntime(
        id: String,
        config: AgentSpawnConfig,
        prepared: PreparedSpawnContext,
        launched: LaunchedProcess
    ) async throws -> PublishedRuntime {
        let generation = UUID()
        processes[id] = launched.process
        adapters[id] = prepared.adapter
        processSnapshot.withLock { $0 = Array(processes.values) }
        publishManagedProcessesChanged()

        let pid = launched.process.processIdentifier
        launched.process.terminationHandler = { [weak self] proc in
            let terminationReason = proc.terminationReason
            let terminationStatus = proc.terminationStatus
            Task {
                await self?.handleProcessExit(
                    id: id,
                    pid: pid,
                    terminationReason: terminationReason,
                    terminationStatus: terminationStatus
                )
            }
        }

        if !launched.process.isRunning {
            handleProcessExit(
                id: id,
                pid: pid,
                terminationReason: launched.process.terminationReason,
                terminationStatus: launched.process.terminationStatus
            )
            throw AgentError.spawnFailed("Process exited before startup completed")
        }

        if shutdownRequested.withLock({ $0 }) {
            suppressExitStatus(for: id, pid: pid)
            await teardownProcess(
                for: id,
                awaitExit: true,
                preserveBufferForDurabilityGrace: false,
                graceSeconds: 1.0
            )
            throw AgentError.spawnFailed("App is shutting down")
        }

        let buffer = EventBuffer()
        eventBuffers[id] = ManagedEventBuffer(generation: generation, allowsReplay: true, buffer: buffer)
        await configureSpawnedState(id: id, config: config, continuity: prepared.sessionLaunch.continuity)
        startStreamTask(
            id: id,
            providerId: config.providerId,
            generation: generation,
            adapter: prepared.adapter,
            launched: launched
        )
        return PublishedRuntime(pid: pid, generation: generation)
    }

    private func configureSpawnedState(id: String, config: AgentSpawnConfig, continuity: SessionContinuity) async {
        let hasImmediateTurn = !(config.initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        await MainActor.run {
            let state = conversationState(for: id)
            state.sessionContinuityNotice = continuity == .restartedFresh
                ? "Claude restarted with a fresh session. Local history is still visible in Alveary, but the live provider context started over."
                : nil
            if hasImmediateTurn {
                state.turnState.beginTurn()
            }
        }
        updateStatus(hasImmediateTurn ? .busy : .idle, for: id)
    }

    private func startStreamTask(
        id: String,
        providerId: String,
        generation: UUID,
        adapter: AgentAdapter,
        launched: LaunchedProcess
    ) {
        let manager = self
        streamTasks[id] = Task { [manager] in
            let stream = manager.readAgentOutput(
                stdout: launched.stdoutReader,
                stderr: launched.stderrReader,
                adapter: adapter
            )
            for await event in stream {
                await manager.handleStreamEvent(event, conversationId: id, generation: generation, providerId: providerId)
            }
            await manager.finishStreamBufferIfCurrent(conversationId: id, generation: generation)
        }
    }

    private func sendInitialPromptIfNeeded(
        id: String,
        config: AgentSpawnConfig,
        prepared: PreparedSpawnContext,
        runtime: PublishedRuntime
    ) async throws {
        guard let initialPrompt = config.initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
              !initialPrompt.isEmpty,
              prepared.adapter.supportsBidirectionalStreaming else {
            return
        }

        do {
            try await sendMessage(initialPrompt, conversationId: id)
        } catch {
            suppressExitStatus(for: id, pid: runtime.pid)
            await teardownProcess(for: id, awaitExit: false, preserveBufferForDurabilityGrace: false)
            await MainActor.run {
                let state = conversationState(for: id)
                state.turnState.endTurn()
                state.clearStreamingText()
            }
            updateStatus(.error, for: id)

            let sendFailure = error.localizedDescription
            if !prepared.isResuming {
                do {
                    try await sessionManager.removeEntry(for: id)
                } catch {
                    throw AgentError.spawnFailed(
                        "Failed to send initial prompt: \(sendFailure). Session cleanup also failed: \(error.localizedDescription)"
                    )
                }
            }
            throw AgentError.spawnFailed("Failed to send initial prompt: \(sendFailure)")
        }
    }

    private func handleStreamEvent(
        _ event: ConversationEvent,
        conversationId: String,
        generation: UUID,
        providerId: String
    ) async {
        guard let managedBuffer = eventBuffers[conversationId], managedBuffer.generation == generation else {
            return
        }
        managedBuffer.buffer.push(event)

        if case .sessionInit(let sessionId) = event, let sessionId {
            do {
                try await sessionManager.updateSessionId(for: conversationId, newSessionId: sessionId)
            } catch {
                print("[AgentsManager] Failed to persist updated session ID for \(conversationId): \(error)")
            }
        }

        switch event {
        case .tokens(_, _, _, let isError, _, _, _, _):
            updateStatus(isError ? .error : .idle, for: conversationId)
        case .error:
            updateStatus(.error, for: conversationId)
        default:
            break
        }

        guard event.canTriggerNotification else {
            return
        }

        let shouldNotify: Bool
        if case .tokens(_, _, _, let isError, _, _, _, let permissionDenials) = event,
           !isError,
           permissionDenials.isEmpty {
            shouldNotify = await MainActor.run {
                let state = conversationState(for: conversationId)
                return state.messageQueue.peekNext() == nil && state.inFlightQueuedMessageID == nil
            }
        } else {
            shouldNotify = true
        }

        guard shouldNotify else {
            return
        }

        await notificationManager.handleEvent(event, conversationId: conversationId)
    }

    private func finishStreamBufferIfCurrent(conversationId: String, generation: UUID) {
        guard let managedBuffer = eventBuffers[conversationId], managedBuffer.generation == generation else {
            return
        }
        managedBuffer.buffer.finishAll()
    }
}

private extension ConversationEvent {
    var canTriggerNotification: Bool {
        switch self {
        case .tokens, .stop, .notification, .error:
            return true
        default:
            return false
        }
    }
}

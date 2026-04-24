import Foundation

extension DefaultAgentsManager {
    func prepareSpawnContext(
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

        let agentConfig = agentConfig(config: config, sessionId: sessionID)
        let sessionLaunch = adapter.sessionLaunch(
            sessionId: sessionID,
            cwd: sessionCwd,
            isResuming: isResuming,
            forkSession: forkSession
        )
        var arguments = try preparedArguments(
            adapter: adapter,
            agentConfig: agentConfig,
            sessionLaunch: sessionLaunch,
            extraArgs: customConfig?.extraArgs
        )

        let hookLaunchConfig = await hookLaunchConfigIfNeeded(
            providerId: config.providerId,
            permissionMode: config.permissionMode,
            conversationId: id
        )
        let providerEnv = mergedProviderEnvironment(
            adapter: adapter,
            agentConfig: agentConfig,
            customEnv: customConfig?.env,
            hookLaunchEnvironment: hookLaunchConfig?.environment
        )
        if let hookLaunchArguments = hookLaunchConfig?.arguments {
            arguments += hookLaunchArguments
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

    func resolveCLIPath(providerId: String, customConfig: ProviderCustomConfig?) async throws -> String {
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

    func launchProcess(
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

    func ensureUnpublishedLaunchStillAllowed(id: String, launched: LaunchedProcess) async throws {
        if pendingKillIds.contains(id) || closingConversationIds.contains(id) {
            await finishUnpublishedSpawnCancellation(launched: launched)
            throw AgentError.spawnFailed("Conversation was closed during spawn")
        }

        if shutdownRequested.withLock({ $0 }) {
            await finishUnpublishedSpawnCancellation(launched: launched, graceSeconds: 1.0)
            throw AgentError.spawnFailed("App is shutting down")
        }
    }

    func publishRuntime(
        id: String,
        config: AgentSpawnConfig,
        prepared: PreparedSpawnContext,
        launched: LaunchedProcess
    ) async throws -> PublishedRuntime {
        let generation = UUID()
        let pid = launched.process.processIdentifier
        publishSpawnedProcess(id: id, prepared: prepared, process: launched.process, pid: pid)

        if !launched.process.isRunning {
            await handleProcessExit(
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
        eventBuffers[id] = ManagedEventBuffer(
            generation: generation, allowsReplay: true,
            acceptsLiveEvents: true, hasDeferredToolStop: false,
            pendingLiveToolApprovals: 0,
            resolvedLiveToolApprovals: [],
            deferredToolStopSessionId: nil, deferredToolStopToolUseId: nil,
            buffer: buffer
        )
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

    func publishSpawnedProcess(
        id: String,
        prepared: PreparedSpawnContext,
        process: Process,
        pid: Int32
    ) {
        processes[id] = process
        adapters[id] = prepared.adapter
        hookTokens[id] = prepared.environment[claudeHookTokenEnvironmentKey]
        processSnapshot.withLock { $0 = Array(processes.values) }
        publishManagedProcessesChanged()

        process.terminationHandler = { [weak self] proc in
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
    }

    func configureSpawnedState(id: String, config: AgentSpawnConfig, continuity: SessionContinuity) async {
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

    func startStreamTask(
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

    func sendInitialPromptIfNeeded(
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
}

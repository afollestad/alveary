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

    func finishUnpublishedSpawnCancellation(
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
        do {
            let launched = try await launchProcess(id: id, config: config, prepared: prepared)
            try await ensureUnpublishedLaunchStillAllowed(id: id, launched: launched)
            let runtime = try await publishRuntime(id: id, config: config, prepared: prepared, launched: launched)
            try await sendInitialPromptIfNeeded(id: id, config: config, prepared: prepared, runtime: runtime)
        } catch {
            await invalidateHookToken(prepared.environment[claudeHookTokenEnvironmentKey])
            throw error
        }
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
}

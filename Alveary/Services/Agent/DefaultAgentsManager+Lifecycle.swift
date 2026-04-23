import Darwin
import Foundation

extension DefaultAgentsManager {
    func sendMessage(_ message: String, conversationId: String) async throws {
        guard !shutdownRequested.withLock({ $0 }),
              !closingConversationIds.contains(conversationId),
              let process = processes[conversationId],
              let adapter = adapters[conversationId],
              let managedBuffer = eventBuffers[conversationId] else {
            throw AgentError.stdinClosed
        }

        let pid = process.processIdentifier
        let generation = managedBuffer.generation

        let previousTail = stdinWriteTails[conversationId]?.task
        let writeID = UUID()
        let pendingWrite = PendingStdinWrite(id: writeID)

        let writeTask = Task<Void, Error> {
            _ = try await previousTail?.value
            try Task.checkCancellation()

            guard !shutdownRequested.withLock({ $0 }),
                  !closingConversationIds.contains(conversationId),
                  stdinWriteTails[conversationId]?.id == writeID,
                  processes[conversationId]?.processIdentifier == pid,
                  eventBuffers[conversationId]?.generation == generation else {
                throw AgentError.stdinClosed
            }

            try adapter.sendMessage(message, to: process)
        }
        pendingWrite.task = writeTask
        stdinWriteTails[conversationId] = pendingWrite

        defer {
            if stdinWriteTails[conversationId]?.id == writeID {
                stdinWriteTails.removeValue(forKey: conversationId)
            }
        }

        try await writeTask.value

        guard processes[conversationId]?.processIdentifier == pid,
              eventBuffers[conversationId]?.generation == generation else {
            return
        }

        updateStatus(.busy, for: conversationId)
    }

    func cancelTurn(conversationId: String) {
        guard let process = processes[conversationId], process.isRunning else {
            return
        }

        Darwin.kill(process.processIdentifier, SIGINT)
    }

    func destroyRuntime(conversationId: String) async throws {
        try await destroyRuntime(conversationId: conversationId, timeout: .seconds(7))
    }

    private func destroyRuntime(conversationId: String, timeout: Duration) async throws {
        kill(conversationId: conversationId)

        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            let stillRunning: Bool
            if let process = processes[conversationId] {
                stillRunning = process.isRunning || spawningIds.contains(conversationId) || reconfiguringIds.contains(conversationId)
            } else {
                stillRunning = spawningIds.contains(conversationId) || reconfiguringIds.contains(conversationId)
            }

            let stillClosing = closingConversationIds.contains(conversationId)
            let sessionRemovalPending = pendingSessionRemovalIds.contains(conversationId)
            if let removalError = pendingSessionRemovalErrors.removeValue(forKey: conversationId) {
                throw AgentError.spawnFailed(
                    "Destructive teardown cleanup failed for \(conversationId): \(removalError)"
                )
            }
            if !stillRunning, !stillClosing, !sessionRemovalPending {
                return
            }

            try await Task.sleep(for: .milliseconds(50))
        }

        throw AgentError.spawnFailed("Timed out waiting for destructive teardown for \(conversationId)")
    }

    func kill(conversationId: String) {
        closingConversationIds.insert(conversationId)
        pendingSessionRemovalIds.insert(conversationId)
        _ = conversationStatesStore.withLock { $0.removeValue(forKey: conversationId) }
        clearStatus(for: conversationId)

        if spawningIds.contains(conversationId) || reconfiguringIds.contains(conversationId) {
            eventBuffers[conversationId]?.allowsReplay = false
            eventBuffers[conversationId]?.buffer.finishAll()
            pendingKillIds.insert(conversationId)
            return
        }

        guard processes[conversationId] != nil else {
            eventBuffers[conversationId]?.allowsReplay = false
            eventBuffers[conversationId]?.buffer.finishAll()
            closingConversationIds.remove(conversationId)
            if pendingSessionRemovalIds.contains(conversationId) {
                Task {
                    await finalizeSessionRemoval(for: conversationId)
                }
            }
            return
        }

        suppressExitStatus(for: conversationId, pid: processes[conversationId]?.processIdentifier)
        eventBuffers[conversationId]?.allowsReplay = false
        Task {
            await teardownProcess(for: conversationId, awaitExit: true, preserveBufferForDurabilityGrace: true)
        }
    }

    func killAll() {
        let ids = Set(processes.keys)
            .union(spawningIds)
            .union(reconfiguringIds)
        for id in ids {
            kill(conversationId: id)
        }
    }

    func reconfigureSession(conversationId: String, config: AgentSpawnConfig) async throws {
        guard !reconfiguringIds.contains(conversationId) else {
            throw AgentError.spawnFailed("Reconfigure already in progress for \(conversationId)")
        }

        reconfiguringIds.insert(conversationId)
        defer { reconfiguringIds.remove(conversationId) }

        let oldPID = processes[conversationId]?.processIdentifier
        suppressExitStatus(for: conversationId, pid: oldPID)
        await teardownProcess(
            for: conversationId,
            awaitExit: true,
            preserveBufferForDurabilityGrace: false
        )

        if pendingKillIds.remove(conversationId) != nil {
            return
        }

        do {
            try await spawnImpl(
                id: conversationId,
                config: config,
                forkSession: true,
                allowReconfigureInFlight: true
            )
        } catch {
            updateStatus(.error, for: conversationId)
            await MainActor.run {
                let state = conversationStatesStore.withLock { $0[conversationId] }
                state?.lastTurnError = "Reconfigure failed: \(error.localizedDescription)"
            }
            throw error
        }
    }

    func teardownProcess(
        for conversationId: String,
        awaitExit: Bool,
        preserveBufferForDurabilityGrace: Bool,
        graceSeconds: TimeInterval = 5
    ) async {
        await invalidateTrackedHookToken(for: conversationId)

        stdinWriteTails[conversationId]?.cancel()
        stdinWriteTails.removeValue(forKey: conversationId)

        streamTasks[conversationId]?.cancel()
        streamTasks.removeValue(forKey: conversationId)

        if preserveBufferForDurabilityGrace {
            eventBuffers[conversationId]?.allowsReplay = false
        }
        eventBuffers[conversationId]?.buffer.finishAll()
        if !preserveBufferForDurabilityGrace {
            eventBuffers.removeValue(forKey: conversationId)
        }

        guard let process = processes[conversationId] else {
            return
        }

        process.terminate()

        guard awaitExit else {
            return
        }

        let deadline = Date().addingTimeInterval(graceSeconds)
        while process.isRunning, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }

        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
            while process.isRunning {
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    func suppressExitStatus(for conversationId: String, pid: Int32?) {
        guard let pid else {
            return
        }

        suppressedExitPIDs[conversationId, default: []].insert(pid)
    }

    private func consumeSuppressedExit(for conversationId: String, pid: Int32) -> Bool {
        guard var pids = suppressedExitPIDs[conversationId], pids.remove(pid) != nil else {
            return false
        }

        if pids.isEmpty {
            suppressedExitPIDs.removeValue(forKey: conversationId)
        } else {
            suppressedExitPIDs[conversationId] = pids
        }
        return true
    }

    func finalizeSessionRemoval(for conversationId: String) async {
        if await sessionManager.hasSession(for: conversationId) {
            let sessionId = await sessionManager.sessionId(for: conversationId)
            await claudeHookServer.removeSessionApprovals(
                conversationId: conversationId,
                sessionId: sessionId
            )
        }
        do {
            try await sessionManager.removeEntry(for: conversationId)
        } catch {
            pendingSessionRemovalErrors[conversationId] = error.localizedDescription
        }
        pendingSessionRemovalIds.remove(conversationId)
    }

    func invalidateTrackedHookToken(for conversationId: String) async {
        let token = hookTokens.removeValue(forKey: conversationId)
        await invalidateHookToken(token)
    }

    func invalidateHookToken(_ token: String?) async {
        guard let token else {
            return
        }

        await claudeHookServer.invalidateToken(token)
    }

    func handleProcessExit(
        id: String,
        pid: Int32,
        terminationReason: Process.TerminationReason,
        terminationStatus: Int32
    ) async {
        guard processes[id]?.processIdentifier == pid else {
            _ = consumeSuppressedExit(for: id, pid: pid)
            return
        }

        processes.removeValue(forKey: id)
        adapters.removeValue(forKey: id)
        await invalidateTrackedHookToken(for: id)
        stdinWriteTails[id]?.cancel()
        stdinWriteTails.removeValue(forKey: id)

        let allProcesses = Array(processes.values)
        processSnapshot.withLock { $0 = allProcesses }
        publishManagedProcessesChanged()

        let suppressVisibleStatus = consumeSuppressedExit(for: id, pid: pid)
        if !suppressVisibleStatus {
            handleVisibleProcessExit(
                id: id,
                terminationReason: terminationReason,
                terminationStatus: terminationStatus
            )
        }

        closingConversationIds.remove(id)
        if pendingSessionRemovalIds.contains(id) {
            Task {
                await finalizeSessionRemoval(for: id)
            }
        }

        if let managedBuffer = eventBuffers[id] {
            scheduleBufferCleanup(for: id, generation: managedBuffer.generation)
        }
    }

    func scheduleBufferCleanup(for id: String, generation expectedGeneration: UUID, delay: Duration = .seconds(300)) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            await self?.runScheduledBufferCleanup(for: id, generation: expectedGeneration)
        }
    }

    func publishManagedProcessesChanged() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .managedProcessesChanged, object: nil)
        }
    }

    private func runScheduledBufferCleanup(for id: String, generation expectedGeneration: UUID) {
        guard processes[id] == nil,
              let managedBuffer = eventBuffers[id],
              managedBuffer.generation == expectedGeneration,
              !managedBuffer.buffer.hasSubscribers else {
            return
        }

        if managedBuffer.buffer.hasUnpersistedEvents {
            scheduleBufferCleanup(for: id, generation: expectedGeneration, delay: .seconds(60))
            return
        }

        eventBuffers.removeValue(forKey: id)
    }

    private func handleVisibleProcessExit(
        id: String,
        terminationReason: Process.TerminationReason,
        terminationStatus: Int32
    ) {
        let exitedCleanly = terminationReason == .exit && terminationStatus == 0
        if exitedCleanly {
            let current = status(for: id)
            if current != .idle, current != .error {
                updateStatus(.stopped, for: id)
            }
        } else {
            updateStatus(.error, for: id)
        }

        Task { @MainActor in
            applyConversationExitOutcome(for: id, exitedCleanly: exitedCleanly)
        }
    }

    @MainActor
    private func applyConversationExitOutcome(for id: String, exitedCleanly: Bool) {
        let state = conversationStatesStore.withLock { $0[id] }
        guard let state else {
            return
        }

        guard state.turnState.isActive else {
            return
        }

        state.turnState.endTurn()
        state.clearStreamingText()
        if var pendingToolApproval = state.pendingToolApproval,
           pendingToolApproval.status != .pending {
            pendingToolApproval.status = .pending
            state.pendingToolApproval = pendingToolApproval
        }

        if state.isCancellingTurn {
            state.isCancellingTurn = false
            state.lastTurnError = nil
            state.lastTurnInterrupted = true
            return
        }

        guard state.lastTurnError == nil else {
            return
        }

        state.lastTurnInterrupted = false
        state.lastTurnError = exitedCleanly
            ? "Agent process exited before finishing the turn"
            : "Agent process crashed unexpectedly"
    }
}

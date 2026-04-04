# Supplement: Agent Runtime Teardown and Reconfiguration

`DefaultAgentsManager` stdin delivery, teardown, reconfigure, and process-exit handling. Continues from [Part 2d: EventBuffer and Agent Lifecycle](part2d-spawn-and-buffer.md).

```swift
    func sendMessage(_ message: String, conversationId: String) async throws {
        guard !shutdownRequested.withLock({ $0 }),
              !closingConversationIds.contains(conversationId),
              let process = processes[conversationId],
              let adapter = adapters[conversationId],
              let managedBuffer = eventBuffers[conversationId] else {
            throw AgentError.stdinClosed  // Process not running — caller should handle this
        }
        let pid = process.processIdentifier
        let generation = managedBuffer.generation
        // Dispatch the blocking pipe write off the actor's serial executor
        // to avoid deadlocking all agent operations if the pipe buffer is full.
        //
        // SAFETY: Process is not Sendable, but this usage is safe because:
        // 1. We only access `process.standardInput` (the stdin Pipe), not mutable Process state.
        // 2. Writes are serialized through `stdinWriteTails` before the detached work starts,
        //    so there is never more than one physical write in flight per conversation.
        // 3. The adapter's sendMessage() only writes to the pipe — no other Process mutation.
        // 4. teardownProcess() does NOT close stdin explicitly — it calls terminate(),
        //    and the pipe closes when the process exits. This avoids a concurrent
        //    closeFile() + write(contentsOf:) race on different threads (FileHandle
        //    is not thread-safe for that). If the process is terminated while a write
        //    is in flight, the write gets EPIPE (catchable via write(contentsOf:)).
        nonisolated(unsafe) let process = process
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
            let writerTask = Task.detached {
                try Task.checkCancellation()
                try adapter.sendMessage(message, to: process)
            }
            pendingWrite.installWriter(writerTask)
            defer { pendingWrite.clearWriter() }
            try await writerTask.value
        }
        pendingWrite.task = writeTask
        stdinWriteTails[conversationId] = pendingWrite
        defer {
            if stdinWriteTails[conversationId]?.id == writeID {
                stdinWriteTails.removeValue(forKey: conversationId)
            }
        }
        try await writeTask.value
        // Guard against race with kill(): if the process was removed while the
        // detached write was in flight, don't set status — kill() already cleaned up.
        // Also guard against replacement: a late completion from an older runtime must
        // not mark the newer process/buffer generation as busy.
        // Cancellation is only strong before the detached write starts. Once
        // `write(contentsOf:)` is inside the blocking Foundation call, the old process
        // may still consume bytes until it exits; the PID/generation guards below are
        // what keep that stale completion from mutating replacement runtime state.
        guard processes[conversationId]?.processIdentifier == pid,
              eventBuffers[conversationId]?.generation == generation else { return }
        updateStatus(.busy, for: conversationId)
    }

    func cancelTurn(conversationId: String) {
        guard let process = processes[conversationId], process.isRunning else { return }
        kill(process.processIdentifier, SIGINT)
    }

    /// Requests process teardown for a conversation. `handleProcessExit()` remains the
    /// single place that removes the tracked `Process`/adapter from dictionaries so we do
    /// not lose sight of a still-running child before it actually exits.
    /// Does NOT remove ConversationState or status — callers decide whether to clean those up.
    /// `preserveBufferForDurabilityGrace` keeps the finished `EventBuffer` installed after
    /// explicit teardown just long enough for a trailing coalesced save to finish.
    /// Explicit teardown removes `ConversationState`, so later restore/reopen flows rely on
    /// durable SwiftData history, not EventBuffer replay.
    /// Reconfigure sets this to false because it installs a replacement buffer immediately.
    private func teardownProcess(
        for conversationId: String,
        awaitExit: Bool,
        preserveBufferForDurabilityGrace: Bool,
        graceSeconds: TimeInterval = 5
    ) async {
        stdinWriteTails[conversationId]?.cancel()
        stdinWriteTails.removeValue(forKey: conversationId)
        streamTasks[conversationId]?.cancel()
        streamTasks.removeValue(forKey: conversationId)
        // Finish all subscriber continuations before touching the buffer.
        // Without this, VMs currently iterating `for await event in stream`
        // would hang forever. finishAll() triggers the safety-net endTurn() +
        // clearStreamingText() in the VM's subscription loop.
        if preserveBufferForDurabilityGrace {
            eventBuffers[conversationId]?.allowsReplay = false
        }
        eventBuffers[conversationId]?.buffer.finishAll()
        if !preserveBufferForDurabilityGrace {
            eventBuffers.removeValue(forKey: conversationId)
        }
        guard let process = processes[conversationId] else { return }
        // Terminate the process first (SIGTERM). The agent handles SIGTERM for
        // graceful shutdown. The stdin pipe closes automatically when the process
        // exits. Do NOT close stdin explicitly before terminate — sendMessage()
        // dispatches writes to a detached task that can overlap with teardown on
        // a different thread, and FileHandle is not thread-safe for concurrent
        // close + write on the same instance.
        process.terminate()

        guard awaitExit else { return }
        let deadline = Date().addingTimeInterval(graceSeconds)
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            while process.isRunning {
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    private func suppressExitStatus(for conversationId: String, pid: Int32?) {
        guard let pid else { return }
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

    /// Manager-owned durable removal path for destructive teardown. `kill()` itself stays
    /// fire-and-forget, but `destroyRuntime()` waits for this helper to finish and throws if
    /// the session-map write failed instead of silently leaving a stale binding on disk.
    private func finalizeSessionRemoval(for conversationId: String) async {
        do {
            try await sessionManager.removeEntry(for: conversationId)
        } catch {
            pendingSessionRemovalErrors[conversationId] = error.localizedDescription
        }
        pendingSessionRemovalIds.remove(conversationId)
    }

    func kill(conversationId: String) {
        closingConversationIds.insert(conversationId)
        pendingSessionRemovalIds.insert(conversationId)
        conversationStatesStore.withLock { $0.removeValue(forKey: conversationId) }
        clearStatus(for: conversationId)
        // If a spawn is in-flight for this ID, defer the kill. spawn()'s defer block
        // checks `pendingKillIds` after completion and runs teardown if the ID is present.
        // During `reconfigureSession()`, the same pending-kill path prevents the replacement
        // spawn from resurrecting a conversation the user just archived/deleted.
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
            await teardownProcess(
                for: conversationId,
                awaitExit: true,
                preserveBufferForDurabilityGrace: true
            )
        }
    }
    func killAll() {
        // Snapshot all lifecycle-owned IDs before iterating — `kill()` mutates several
        // collections, and shutdown/archive paths must also catch conversations that are
        // only in spawn/reconfigure bookkeeping and have not published a child yet.
        let ids = Set(processes.keys)
            .union(spawningIds)
            .union(reconfiguringIds)
        for id in ids { kill(conversationId: id) }
    }

    /// Single public owner for destructive teardown. Archive/delete flows and first-run
    /// rollback use this instead of open-coding `kill()` + wait loops + direct
    /// `SessionManager.removeEntry()` calls in higher layers.
    func destroyRuntime(conversationId: String, timeout: Duration = .seconds(7)) async throws {
        kill(conversationId: conversationId)
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            let stillRunning = if let process = processes[conversationId] {
                process.isRunning || spawningIds.contains(conversationId) || reconfiguringIds.contains(conversationId)
            } else {
                spawningIds.contains(conversationId) || reconfiguringIds.contains(conversationId)
            }
            let stillClosing = closingConversationIds.contains(conversationId)
            let sessionRemovalPending = pendingSessionRemovalIds.contains(conversationId)
            if let removalError = pendingSessionRemovalErrors.removeValue(forKey: conversationId) {
                throw AgentError.spawnFailed(
                    "Destructive teardown cleanup failed for \(conversationId): \(removalError)"
                )
            }
            if !stillRunning && !stillClosing && !sessionRemovalPending {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw AgentError.spawnFailed("Timed out waiting for destructive teardown for \(conversationId)")
    }

    /// Reconfigure the current process with new session-level spawn flags (model,
    /// permission mode, effort). In the normal Claude path this is a
    /// `--resume ... --fork-session` replacement; if Claude's session artifact is missing,
    /// the adapter falls back to a fresh `--session-id <same-uuid>` launch under the same
    /// app-side binding.
    /// ConversationState is intentionally preserved — message queue, input draft, grouper
    /// cache, and staged context all survive the fork.
    func reconfigureSession(conversationId: String, config: AgentSpawnConfig) async throws {
        guard !reconfiguringIds.contains(conversationId) else {
            throw AgentError.spawnFailed("Reconfigure already in progress for \(conversationId)")
        }
        reconfiguringIds.insert(conversationId)
        defer { reconfiguringIds.remove(conversationId) }
        // Tear down the existing process, stream task, and old event buffer.
        // Does NOT remove ConversationState or status — those survive the fork.
        // Wait for the old PID to exit before spawning the replacement so the app never
        // loses track of a still-running child or overlaps two processes for one chat.
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
            // Re-spawn with --fork-session so Claude creates a new session ID
            // but preserves the full conversation context from the old session.
            try await spawnImpl(
                id: conversationId,
                config: config,
                forkSession: true,
                allowReconfigureInFlight: true
            )
        } catch {
            // The old process is gone but the new one failed to start.
            // Surface the error so the user knows what happened.
            updateStatus(.error, for: conversationId)
            await MainActor.run {
                let state = conversationStatesStore.withLock { $0[conversationId] }
                state?.lastTurnError = "Reconfigure failed: \(error.localizedDescription)"
            }
            throw error
        }
    }

    /// Lock-protected snapshot for synchronous access during shutdown.
    /// Updated whenever `processes` changes. Avoids breaking actor isolation
    /// in `applicationWillTerminate` (which is synchronous).
    /// Accessed via the nonisolated `allProcessesSnapshot` property below.
    private let processSnapshot = OSAllocatedUnfairLock(initialState: [Process]())

    /// Nonisolated accessor for synchronous shutdown in `applicationWillTerminate`.
    nonisolated var allProcessesSnapshot: [Process] {
        processSnapshot.withLock { $0 }
    }

    /// Narrower than `isRunning(conversationId:)`: returns true only after a child has
    /// been published into `processes`, not while a spawn/reconfigure is merely in flight.
    func hasTrackedProcess(conversationId: String) -> Bool {
        processes[conversationId] != nil
    }

    func hasInflightLifecycle(conversationId: String) -> Bool {
        spawningIds.contains(conversationId) || reconfiguringIds.contains(conversationId)
    }

    func allProcesses() -> [Process] { Array(processes.values) }
    func isRunning(conversationId: String) -> Bool {
        guard let process = processes[conversationId] else {
            return spawningIds.contains(conversationId) || reconfiguringIds.contains(conversationId)
        }
        return process.isRunning || spawningIds.contains(conversationId) || reconfiguringIds.contains(conversationId)
    }

    private func handleProcessExit(
        id: String,
        pid: Int32,
        terminationReason: Process.TerminationReason,
        terminationStatus: Int32
    ) {
        // Guard against stale termination handlers: if the process for this ID
        // has been replaced (e.g. by reconfigureSession), skip visible cleanup but still
        // consume any suppression token that belonged to the stale PID so it cannot leak
        // forward and accidentally suppress a future real exit if that PID is reused.
        guard processes[id]?.processIdentifier == pid else {
            _ = consumeSuppressedExit(for: id, pid: pid)
            return
        }
        streamTasks[id]?.cancel()
        streamTasks.removeValue(forKey: id)
        processes.removeValue(forKey: id)
        adapters.removeValue(forKey: id)
        stdinWriteTails[id]?.cancel()
        stdinWriteTails.removeValue(forKey: id)
        let allProcesses = Array(processes.values)
        processSnapshot.withLock { $0 = allProcesses }
        publishManagedProcessesChanged()
        // Explicit teardown paths (`kill()` / `reconfigureSession()`) already decided
        // what the visible status should be. Do not resurrect a terminal status when the
        // expected process exit finally arrives.
        let suppressVisibleStatus = consumeSuppressedExit(for: id, pid: pid)
        if !suppressVisibleStatus {
            if terminationReason == .exit && terminationStatus == 0 {
                // Clean EOF without a fatal stream error. If the turn had already emitted
                // a `.tokens` event, status may already be .idle/.error; only downgrade to
                // .stopped when the stream ended cleanly without a more specific terminal state.
                let current = status(for: id)
                if current != .idle && current != .error {
                    updateStatus(.stopped, for: id)
                }
            } else {
                updateStatus(.error, for: id)
                Task { @MainActor in
                    let state = conversationStatesStore.withLock { $0[id] }
                    if state?.lastTurnError == nil {
                        state?.lastTurnError = "Agent process crashed unexpectedly"
                    }
                }
            }
        }
        // Destructive teardown keeps the session binding until the old child is actually
        // gone so startup orphan cleanup can still prove ownership if the app crashes in
        // the middle of kill/archive/delete. Once exit is confirmed here, the binding can
        // be removed asynchronously.
        closingConversationIds.remove(id)
        if pendingSessionRemovalIds.contains(id) {
            Task {
                await finalizeSessionRemoval(for: id)
            }
        }
        // EventBuffer is intentionally kept briefly — the VM may still need to
        // read buffered events after the process exits (e.g. final result).
        // Schedule cleanup only after the durable save boundary has caught up. If a
        // coalesced save failed, the buffer may still hold the only replayable copy.
        // This runs even for expected/suppressed exits so explicit kill/archive flows do
        // not leave preserved buffers immortal after persistence eventually succeeds.
        if let managedBuffer = eventBuffers[id] {
            scheduleBufferCleanup(for: id, generation: managedBuffer.generation)
        }
    }

    /// Evicts an orphaned EventBuffer if no subscriber has attached within the grace period.
    /// This prevents unbounded memory growth when processes crash and the user never
    /// returns to that conversation.
    private func scheduleBufferCleanup(for id: String, generation expectedGeneration: UUID, delay: Duration = .seconds(300)) {
        Task {
            try? await Task.sleep(for: delay)
            // Only evict the EventBuffer if the process is still gone and no VM is listening.
            // Match by generation: a respawned process may have installed a replacement
            // buffer for the same conversation ID, and the old cleanup timer must not steal
            // that newer buffer's full grace period or replayability.
            // ConversationState is NOT evicted here — it holds user-facing state (input draft,
            // selected model, queued messages, staged context, grouper cache) that should
            // survive ordinary in-app process teardown and navigation. It is explicitly
            // removed by `kill()` and also disappears on full app termination/relaunch
            // because it is in-memory service state rather than SwiftData.
            guard processes[id] == nil,
                  let managedBuffer = eventBuffers[id],
                  managedBuffer.generation == expectedGeneration,
                  !managedBuffer.buffer.hasSubscribers else { return }
            if managedBuffer.buffer.hasUnpersistedEvents {
                // Persistence lagged behind the original cleanup window. Re-arm a shorter
                // follow-up check instead of keeping this orphaned buffer forever.
                scheduleBufferCleanup(for: id, generation: expectedGeneration, delay: .seconds(60))
                return
            }
            eventBuffers.removeValue(forKey: id)
        }
    }

    private func publishManagedProcessesChanged() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .managedProcessesChanged, object: nil)
        }
    }
```

**Unit tests for DefaultAgentsManager process-exit handling** (in addition to the public-method tests in Part 2c):
- Non-zero exit or uncaught signal sets `.error`, not `.stopped`
- Clean exit without a prior `.tokens` event sets `.stopped`
- Clean exit after a `.tokens` event does **not** clobber `.idle` / `.error`
- Explicit `kill()` / `reconfigureSession()` exits do **not** publish a later `.stopped` / `.error` when the expected termination handler fires
- Unexpected non-zero / signaled exits set `.error` status and populate `ConversationState.lastTurnError` if no more specific turn error already exists, so the chat surface gets the same inline crash banner even when no terminal `.tokens` arrived
- Explicit `kill()` preserves the finished `EventBuffer` only for a short durability grace window (trailing coalesced saves), marks that `ManagedBuffer` as `allowsReplay = false`, and still lets `markPersisted(generation:upTo:)` evict it later; `reconfigureSession()` discards the old buffer before installing the replacement
- Suppressed exits still schedule buffer cleanup, and `markPersisted(generation:upTo:)` re-arms cleanup only for the matching generation so preserved buffers are eventually evicted after durability catches up without advancing a replacement buffer
- Live-process snapshot changes publish `.managedProcessesChanged` on both spawn and exit, including expected/suppressed exits
- `kill()` after an already-finished crash/EOF still calls `finishAll()` on the retained buffer, so subscribed VMs do not hang forever waiting on a stream that no process will ever close
- `killAll()` snapshots `processes.keys ∪ spawningIds ∪ reconfiguringIds`, so late unpublished children are still marked for deferred teardown instead of slipping past the kill-all request
- `destroyRuntime()` is the single public owner for destructive teardown: archive/delete/setup-rollback use it instead of layering their own wait loop and `SessionManager.removeEntry()` calls on top of `kill()`
- `destroyRuntime()` throws when deferred `sessionManager.removeEntry()` fails after child exit, instead of reporting teardown success with a stale on-disk binding
- `reconfigureSession()` waits for old-process exit and sends SIGKILL after timeout before spawning the replacement
- Late old-generation stream events after `reconfigureSession()` / `kill()` are ignored by PID + generation guards: they do not persist, do not touch the replacement `ConversationState`, and do not mutate the new runtime's visible status/grouping
- `sendMessage()` rejects conversations that are already closing or globally shutting down before launching a new detached writer, but a writer already inside `write(contentsOf:)` is only interrupted by the old process exiting
- `kill()` clears UI state immediately yet delays `sessionManager.removeEntry()` until `handleProcessExit()` confirms the old child is gone; `destroyRuntime()` waits for that manager-owned removal to finish before returning, and deferred-kill spawn cancellation removes the entry only after the unpublished child is synchronously stopped
- Durable session-removal failures are recorded and surfaced back through `destroyRuntime()` / spawn-failure cleanup instead of being swallowed with `try?`

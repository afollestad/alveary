# Part 2d: EventBuffer and Agent Lifecycle

EventBuffer, spawn, subscribe, and replay bookkeeping. Runtime teardown and reconfigure handling continue in the [Agent Runtime Teardown supplement](supplement-agent-runtime-teardown.md). Continues from Part 2c.

## Implementation Status

- [x] `EventBuffer`, `ManagedEventBuffer`, replay subscriptions, persisted-boundary tracking, and delayed cleanup are implemented in the repo.
- [x] Spawn-time replay publication, `markPersisted`, and buffer cleanup scheduling are implemented in `DefaultAgentsManager`.
- [x] Regression coverage exists for replay, finish, and eviction behavior in `SkepTests/Services/EventBufferTests.swift`.
- [x] SwiftData persistence/replay consumption from `ConversationViewModel` is implemented in the repo and covered by focused replay/VM regression tests.

## EventBuffer Contract

`EventBuffer` is a short-lived replay and durability aid, not a second source of truth. Durable chat history still lives in SwiftData, while the buffer only bridges three gaps:

- VM disconnects and reconnects within the same app launch.
- Coalesced-save lag between "event observed" and "event durably persisted."
- Process exit / teardown windows where trailing events still need replay or cleanup.

Three invariants matter here:

- Replay cursors are **global exclusive event counts**, not array offsets. `baseOffset` translates those global cursors back into the compacted in-memory slice after eviction.
- `subscribe(afterIndex:)` must replay the saved snapshot, then perform a gap check, then register the live continuation under one lock window. That prevents a concurrent `push()` from sneaking a newer event ahead of replay.
- `finishAll()` closes late subscribers cleanly. A finished buffer may still replay its retained snapshot during durability grace, but it must then end the stream immediately so VM cleanup (`endTurn()`, `clearStreamingText()`) still runs.

The subscribe ordering looks like this:

```text
subscribe(afterIndex: 50)           concurrent push(#56)
snapshot #51...#55 under lock       blocked on same lock
unlock                              append #55
replay snapshot                     unlock
lock again                          blocked on same lock
replay missed tail (#56)
register continuation
unlock                              future pushes now go live
```

## Lifecycle Retention Matrix

The runtime has three different kinds of state with intentionally different lifetimes: the child `Process`, the short-lived `EventBuffer`, and launch-scoped `ConversationState`. The table below is the fast reference for which pieces survive each lifecycle path.

| Path | Process | EventBuffer | Replayable? | `ConversationState` | Session map entry | Visible status |
|---|---|---|---|---|---|---|
| Fresh spawn / steady-state run | Live child tracked in `processes` | Live buffer for current generation | Yes | Preserved | Preserved | `.idle` or `.busy` |
| Unexpected exit / crash / EOF | Removed by `handleProcessExit()` | Temporarily retained for late replay + durability cleanup | Yes | Preserved | Preserved | `.error` or `.stopped` from exit handling |
| Explicit `kill()` / archive / delete | Terminated, awaited, then removed | Retained only for trailing durability grace | No (`allowsReplay = false`) | Removed | Removed | Cleared immediately via `clearStatus(for:)` |
| `reconfigureSession()` fork | Old child terminated; replacement child installed | Old buffer removed, replacement generation installed immediately | New generation only | Preserved | Preserved, then updated from new `system/init` session ID | No explicit clear; replacement spawn restores `.idle`/`.busy` |
| Kill requested during in-flight spawn / reconfigure | Newly launched child is torn down before it becomes usable | No user-replayable buffer survives that deferred kill path | No | Removed | Removed | Cleared |

Two concrete examples are worth keeping in mind:

- **Archive/delete is durable-history-only after teardown.** The finished buffer may linger briefly so a trailing coalesced save can finish, but replay is intentionally disabled. Reopening that thread later must rebuild from SwiftData, not from a launch-scoped buffer.
- **Fork-session reconfigure keeps UI state, not runtime generation.** The existing grouped history, queue, draft, and selected-model override survive because `ConversationState` survives; the old buffer generation does not. The replacement session always starts with a fresh buffer generation and fresh replay cursors.

```swift
    final class EventBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [ConversationEvent] = []
        private var continuations: [UUID: AsyncStream<ConversationEvent>.Continuation] = [:]
        /// Global durable boundary for eviction (exclusive cursor).
        private var persistedIndex: Int = 0
        /// Late subscribers replay once, then finish.
        private var isFinished: Bool = false
        /// Global-to-local index translation after eviction.
        private var baseOffset: Int = 0
        /// Target replay-window size after a batch compaction. Because persisted prefixes
        /// are evicted in batches, the live retained window can sit slightly above this
        /// between evictions.
        private static let maxRetained = 5000
        /// Avoid O(n) `removeFirst` compaction on every event once the buffer is full.
        /// Instead, evict persisted prefixes in batches.
        private static let evictionBatch = 256

        func push(_ event: ConversationEvent) {
            lock.lock()
            guard !isFinished else {
                lock.unlock()
                return
            }
            events.append(event)
            // Evict only the durably persisted prefix, and do it in batches so a long
            // session does not pay array-compaction cost on every single push after the
            // buffer crosses the retention threshold.
            if events.count > Self.maxRetained + Self.evictionBatch && persistedIndex > baseOffset {
                let localPersisted = persistedIndex - baseOffset
                let overflow = events.count - Self.maxRetained
                let evictCount = min(localPersisted, max(Self.evictionBatch, overflow))
                if evictCount > 0 {
                    events.removeFirst(evictCount)
                    baseOffset += evictCount
                }
            }
            // Yield while holding the lock to preserve ordering.
            let active = continuations.values
            for continuation in active { continuation.yield(event) }
            lock.unlock()
        }

        /// Advance the durable boundary (exclusive cursor: the next event count
        /// the durable store no longer needs replayed).
        func markPersisted(upTo index: Int) {
            lock.lock()
            persistedIndex = max(persistedIndex, index)
            lock.unlock()
        }

        /// Replay buffered events after the caller's exclusive cursor, then attach to the live stream.
        func subscribe(afterIndex: Int = 0) -> (stream: AsyncStream<ConversationEvent>, id: UUID) {
            let subId = UUID()
            // Snapshot first; register only after replay.
            lock.lock()
            // Translate the global cursor into the compacted slice.
            let localIndex = max(afterIndex - baseOffset, 0)
            let snapshot = events[min(localIndex, events.count)...]
            let snapshotGlobalEnd = baseOffset + events.count
            lock.unlock()
            let stream = AsyncStream<ConversationEvent> { continuation in
                // Replay the snapshot before attaching to live events.
                for event in snapshot { continuation.yield(event) }
                // Gap-check and registration share one lock window.
                self.lock.lock()
                let localStart = max(snapshotGlobalEnd - self.baseOffset, 0)
                let safeStart = min(localStart, self.events.count)
                let missed = Array(self.events[safeStart...])
                for event in missed { continuation.yield(event) }
                // Finished buffers replay once, then end immediately.
                if self.isFinished {
                    continuation.finish()
                } else {
                    self.continuations[subId] = continuation
                }
                self.lock.unlock()
                continuation.onTermination = { [weak self] _ in
                    self?.unsubscribe(subId)
                }
            }
            return (stream, subId)
        }

        func unsubscribe(_ id: UUID) {
            lock.lock()
            continuations.removeValue(forKey: id)
            lock.unlock()
        }

        /// Current in-memory replay window after any persisted-prefix eviction. This is
        /// not the global event count, and batched eviction may leave it slightly above
        /// `maxRetained` until the next compaction.
        var retainedCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return events.count
        }

        var hasSubscribers: Bool {
            lock.lock()
            defer { lock.unlock() }
            return !continuations.isEmpty
        }

        /// Cleanup must not drop the only replayable copy after a failed save.
        var hasUnpersistedEvents: Bool {
            lock.lock()
            defer { lock.unlock() }
            return (baseOffset + events.count) > persistedIndex
        }

        /// Replay still works, but new subscribers finish immediately.
        func finishAll() {
            lock.lock()
            isFinished = true
            // Remove first to avoid reentrant `onTermination` deadlock.
            let toFinish = Array(continuations.values)
            continuations.removeAll()
            lock.unlock()
            for continuation in toFinish {
                continuation.finish()
            }
        }
    }

    struct AgentEventSubscription: Sendable {
        let generation: UUID
        let stream: AsyncStream<ConversationEvent>
    }

    struct ManagedEventBuffer: Sendable {
        let generation: UUID
        var allowsReplay: Bool
        let buffer: EventBuffer
    }

    final class PendingStdinWrite {
        let id: UUID
        var task: Task<Void, Error>?

        init(id: UUID) {
            self.id = id
        }

        func cancel() {
            task?.cancel()
        }
    }

    /// Used when shutdown or a deferred kill lands before the child has been published
    /// into `processes`. No termination handler exists yet, so this path must stop the
    /// local `Process` directly instead of relying on `handleProcessExit()`.
    private func finishUnpublishedSpawnCancellation(
        process: Process,
        stdin: Pipe,
        stdout: Pipe,
        stderr: Pipe,
        graceSeconds: TimeInterval = 5
    ) async {
        process.terminate()
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
        stdin.fileHandleForWriting.closeFile()
        stdin.fileHandleForReading.closeFile()
        stdout.fileHandleForWriting.closeFile()
        stdout.fileHandleForReading.closeFile()
        stderr.fileHandleForWriting.closeFile()
        stderr.fileHandleForReading.closeFile()
    }

    func spawn(id: String, config: AgentSpawnConfig, forkSession: Bool = false) async throws {
        try await spawnImpl(
            id: id,
            config: config,
            forkSession: forkSession,
            allowReconfigureInFlight: false
        )
    }

    private func spawnImpl(
        id: String,
        config: AgentSpawnConfig,
        forkSession: Bool,
        allowReconfigureInFlight: Bool
    ) async throws {
        guard !shutdownRequested.withLock({ $0 }) else {
            throw AgentError.spawnFailed("App is shutting down")
        }
        guard !closingConversationIds.contains(id) else {
            throw AgentError.spawnFailed("Conversation is closing")
        }
        // Guard against concurrent spawn for the same conversation. spawn() has multiple
        // await points that yield the actor — without this, a second spawn() or kill()
        // could interleave and create orphaned processes or remove state prematurely.
        guard !spawningIds.contains(id) else {
            throw AgentError.spawnFailed("Spawn already in progress for \(id)")
        }
        guard allowReconfigureInFlight || !reconfiguringIds.contains(id) else {
            throw AgentError.spawnFailed("Reconfigure already in progress for \(id)")
        }
        if let existing = processes[id], existing.isRunning {
            throw AgentError.spawnFailed("Agent already running for \(id). Use reconfigureSession() or kill() before spawning again")
        }
        spawningIds.insert(id)
        defer {
            spawningIds.remove(id)
            // If kill() was called while spawn was in-flight, it deferred to us.
            // Now that spawn is complete, honor the kill request immediately.
            if pendingKillIds.remove(id) != nil {
                suppressExitStatus(for: id, pid: processes[id]?.processIdentifier)
                eventBuffers[id]?.allowsReplay = false
                if processes[id] != nil {
                    Task {
                        await teardownProcess(
                            for: id,
                            awaitExit: true,
                            preserveBufferForDurabilityGrace: true
                        )
                    }
                }
                conversationStatesStore.withLock { $0.removeValue(forKey: id) }
                clearStatus(for: id)
                if processes[id] == nil {
                    closingConversationIds.remove(id)
                    if pendingSessionRemovalIds.contains(id) {
                        Task {
                            await finalizeSessionRemoval(for: id)
                        }
                    }
                }
            }
        }

        // 1. Resolve custom provider config early — needed for CLI path override (step 2)
        //    and extra args/env (step 4b).
        // await: SettingsService is @MainActor; actor hops to read the value.
        let customConfig = await settingsService.current.providerConfigs[config.providerId]

        // 2. Get CLI path. Custom CLI path from user settings takes precedence over
        //    the auto-detected path from ProviderDetectionService (which resolves
        //    via `which` against the registry's `commands` array).
        let cliPath: String
        if let customCli = customConfig?.cli, !customCli.isEmpty, customCli.contains("/") {
            // Explicit filesystem path override — spawn directly.
            cliPath = customCli
        } else {
            // Named custom commands must still go through provider detection so the
            // same resolution/auth/error semantics apply as registry commands.
            if await providerDetection.resolvedPath(for: config.providerId) == nil ||
                !(customConfig?.cli?.isEmpty ?? true) {
                await providerDetection.checkProvider(config.providerId)
            }
            guard let detectedPath = await providerDetection.resolvedPath(for: config.providerId) else {
                throw AgentError.cliNotInstalled(config.providerId)
            }
            cliPath = detectedPath
        }

        // 3. Get or create adapter for this provider
        let adapter = resolveAdapter(for: config.providerId)

        // 4. Reconcile the session entry with the current cwd/provider before building args.
        // Session identity uses the canonicalized real path, not the raw launch string:
        // Claude's `system/init.cwd`, its on-disk session directory, and live-process cwd
        // inspection all resolve symlinks. Without this normalization, launching a thread
        // from `/tmp/link/project` and later scanning a live orphan at `/private/tmp/...`
        // would look like two different bindings.
        let sessionCwd = URL(fileURLWithPath: config.workingDirectory)
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
        // This runs on every spawn path, not just first spawn, so a conversation that
        // moved from project root → worktree (or switched providers) rotates to a new
        // UUID and uses `--session-id` instead of incorrectly attempting `--resume`.
        let isResuming = await sessionManager.createEntry(
            conversationId: id,
            cwd: sessionCwd,
            providerId: config.providerId
        )
        let sessionId = await sessionManager.sessionId(for: id)

        // 5. Convert spawn config to adapter config
        let agentConfig = AgentConfig(
            providerId: config.providerId,
            sessionId: sessionId,
            workingDirectory: config.workingDirectory,
            permissionMode: config.permissionMode,
            model: config.model,
            effort: config.effort,
            initialPrompt: config.initialPrompt
        )

        // 6. Build args and environment
        var args = adapter.buildArgs(config: agentConfig)
        let sessionLaunch = adapter.sessionLaunch(
            sessionId: sessionId,
            cwd: sessionCwd,
            isResuming: isResuming,
            forkSession: forkSession
        )
        args += sessionLaunch.args

        // 6b. Apply per-provider custom config overrides (extra args and env).
        // Custom CLI path was already applied in step 2 above.
        if let extraArgs = customConfig?.extraArgs, !extraArgs.isEmpty {
            // Lightweight shell-style quoting is supported for grouped values like
            // `--label "value with spaces"`, but we still do not perform expansion or globbing.
            args += try parseExtraArgs(extraArgs)
        }
        var providerEnv = adapter.envOverrides(config: agentConfig)
        if let customEnv = customConfig?.env {
            providerEnv.merge(customEnv) { _, custom in custom }
        }
        let env = environmentBuilder.buildEnvironment(providerEnv: providerEnv)

        // 7. Spawn the process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: config.workingDirectory)
        process.environment = env
        let stdin = Pipe(); let stdout = Pipe(); let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            // The parent only keeps the stdin writer plus stdout/stderr readers.
            // Close the unused ends immediately so extra parent-held descriptors do
            // not delay EOF or make teardown/read-side ownership ambiguous.
            stdin.fileHandleForReading.closeFile()
            stdout.fileHandleForWriting.closeFile()
            stderr.fileHandleForWriting.closeFile()
        } catch {
            let spawnFailure = error.localizedDescription
            // Clean up pipes and dangling session entry on spawn failure
            stdin.fileHandleForWriting.closeFile()
            stdin.fileHandleForReading.closeFile()
            stdout.fileHandleForWriting.closeFile()
            stdout.fileHandleForReading.closeFile()
            stderr.fileHandleForWriting.closeFile()
            stderr.fileHandleForReading.closeFile()
            var sessionCleanupFailure: String?
            if !isResuming {
                do {
                    try await sessionManager.removeEntry(for: id)
                } catch {
                    sessionCleanupFailure = error.localizedDescription
                }
            }
            // The CLI may have moved (e.g. user updated it). Re-run provider detection
            // so the resolved path/status cache is refreshed for the next user action.
            await providerDetection.checkProvider(config.providerId)
            if let sessionCleanupFailure {
                throw AgentError.spawnFailed(
                    "Spawn failed: \(spawnFailure). Session cleanup also failed: \(sessionCleanupFailure)"
                )
            }
            throw AgentError.spawnFailed(spawnFailure)
        }
        // A deferred archive/delete may have arrived while the spawn was still resolving
        // settings, session state, or provider detection. Honor it before publishing any
        // process/buffer/status state or sending an initial prompt.
        if pendingKillIds.contains(id) || closingConversationIds.contains(id) {
            await finishUnpublishedSpawnCancellation(
                process: process,
                stdin: stdin,
                stdout: stdout,
                stderr: stderr
            )
            throw AgentError.spawnFailed("Conversation was closed during spawn")
        }
        // Shutdown may begin while this spawn is suspended in provider detection,
        // session reconciliation, or `process.run()`. If that happens, tear down the
        // just-launched child before publishing it to the tracked-process snapshot so
        // `applicationWillTerminate` cannot miss and orphan it.
        if shutdownRequested.withLock({ $0 }) {
            await finishUnpublishedSpawnCancellation(
                process: process,
                stdin: stdin,
                stdout: stdout,
                stderr: stderr,
                graceSeconds: 1.0
            )
            throw AgentError.spawnFailed("App is shutting down")
        }

        let generation = UUID()
        processes[id] = process
        adapters[id] = adapter
        // Capture outside the @Sendable closure — actor-isolated properties
        // cannot be referenced inside withLock's closure.
        let allProcesses = Array(processes.values)
        processSnapshot.withLock { $0 = allProcesses }
        publishManagedProcessesChanged()

        // Set a termination handler to clean up when the process exits unexpectedly.
        // Capture the PID (Int32, Sendable) for the stale-process guard instead of
        // the Process reference (non-Sendable) to avoid Swift 6 strict concurrency errors.
        let pid = process.processIdentifier
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
        if !process.isRunning {
            await handleProcessExit(
                id: id,
                pid: pid,
                terminationReason: process.terminationReason,
                terminationStatus: process.terminationStatus
            )
            throw AgentError.spawnFailed("Process exited before startup completed")
        }

        // Shutdown can still begin in the narrow window after the first guard above and
        // around publication into the tracked snapshot. Re-check here, after publication
        // and termination-handler installation, so a late child tears itself down instead
        // of relying on `applicationWillTerminate()`'s earlier snapshot to notice it.
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

        // 8. Start reading stdout in a service-owned task.
        // Events are pushed to the EventBuffer, which persists independently of any
        // ConversationViewModel. VMs subscribe/unsubscribe as users navigate.
        let buffer = EventBuffer()
        eventBuffers[id] = ManagedEventBuffer(
            generation: generation,
            allowsReplay: true,
            buffer: buffer
        )
        // updateStatus(), clearStatus(for:), statusSnapshot, status(for:), and
        // allStatuses are defined in "Reactive Agent Status for the Sidebar" (Part 2g). Add them to
        // DefaultAgentsManager when building this section — they're simple lock-protected
        // properties with no external dependencies.
        let hasImmediateTurn = !(config.initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        await MainActor.run {
            let state = conversationState(for: id)
            if sessionLaunch.continuity == .restartedFresh {
                state.sessionContinuityNotice = "Claude restarted with a fresh session. Local history is still visible in Skep, but the live provider context started over."
            } else {
                state.sessionContinuityNotice = nil
            }
        }
        updateStatus(hasImmediateTurn ? .busy : .idle, for: id)
        if hasImmediateTurn {
            await MainActor.run {
                // Manager-owned immediate turns must go through the same single-owner
                // state factory as VM init; an optional store lookup would miss a brand-
                // new conversation and leave TurnState idle while the runtime is already busy.
                let state = conversationState(for: id)
                state.turnState.beginTurn()
            }
        }
        streamTasks[id] = Task {
            let stream = readAgentOutput(stdout: stdout.fileHandleForReading, stderr: stderr.fileHandleForReading, adapter: adapter)
            for await event in stream {
                guard let managedBuffer = eventBuffers[id], managedBuffer.generation == generation else {
                    continue  // Stale reader from a replaced or explicitly torn-down runtime.
                }
                managedBuffer.buffer.push(event)
                // Capture the session ID from system/init events. After a --fork-session
                // re-spawn, the new session ID must be persisted so future resumes use it.
                if case .sessionInit(let sessionId) = event, let sessionId {
                    do {
                        try await sessionManager.updateSessionId(for: id, newSessionId: sessionId)
                    } catch {
                        // Keep the live replacement runtime. `DefaultSessionManager`
                        // updates the in-memory binding before attempting the durable
                        // write, so the current launch continues on the new forked
                        // session even if the file write fails. The remaining risk is a
                        // later relaunch resuming the stale pre-fork session if no
                        // subsequent persist succeeds before the app exits.
                        print("[AgentsManager] Failed to persist updated session ID for \(id): \(error)")
                    }
                }
                // Update observable status for the sidebar.
                if case .tokens(_, _, _, let isError, _, _, _, _) = event {
                    updateStatus(isError ? .error : .idle, for: id)
                } else if case .error = event {
                    updateStatus(.error, for: id)
                }
                // NotificationManager fires at the service layer, independent of any VM.
                // Suppress a plain completion notification if a queued head is about to
                // auto-send immediately — the user-visible thread is still effectively busy.
                let shouldNotify = await MainActor.run {
                    if case .tokens(_, _, _, let isError, _, _, _, let permissionDenials) = event,
                       !isError, permissionDenials.isEmpty {
                        let state = conversationState(for: id)
                        return state.messageQueue.peekNext() == nil && state.inFlightQueuedMessageID == nil
                    }
                    return true
                }
                guard shouldNotify else { continue }
                // Use the human-readable provider name (e.g. "Claude Code") from the
                // registry, not the raw provider ID (e.g. "claude"). Thread name is
                // not available from AgentSpawnConfig — resolve it from the conversation
                // model when needed, or accept nil for the service-layer notification
                // (the VM layer can provide it if a richer notification is needed later).
                let providerName = providerRegistry.provider(for: config.providerId)?.name ?? config.providerId
                await notificationManager.handleEvent(event, providerName: providerName, threadName: nil)
            }
            // Stream ended (stdout EOF — process exited or was killed). Finish all
            // subscriber continuations so VMs' `for await` loops end and the safety-net
            // endTurn()/clearStreamingText() runs. Without this, a crash (no `result`
            // event) would leave VMs stuck in busy state until buffer cleanup (~5 min).
            guard eventBuffers[id]?.generation == generation else { return }
            buffer.finishAll()
        }

        // Kick off the first turn immediately when the spawn path carries an initialPrompt.
        // For bidirectional providers, this is a post-spawn stdin write using the same
        // serialized pipe path as normal sendMessage(). Future single-turn providers can instead
        // consume `config.initialPrompt` inside `buildArgs(config:)`.
        if let initialPrompt = config.initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !initialPrompt.isEmpty,
           adapter.supportsBidirectionalStreaming {
            do {
                try await sendMessage(initialPrompt, conversationId: id)
            } catch {
                suppressExitStatus(for: id, pid: pid)
                await teardownProcess(
                    for: id,
                    awaitExit: false,
                    preserveBufferForDurabilityGrace: false
                )
                await MainActor.run {
                    let state = conversationState(for: id)
                    state.turnState.endTurn()
                    state.clearStreamingText()
                }
                updateStatus(.error, for: id)
                let sendFailure = error.localizedDescription
                if !isResuming {
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

    /// Subscribe to events for a conversation. Returns a stream that replays
    /// any missed events (from `afterIndex`) and then yields live events.
    /// Called by ConversationViewModel on init; the subscription is cancelled on deinit.
    func subscribe(conversationId: String, afterIndex: Int = 0) -> AgentEventSubscription? {
        guard let managedBuffer = eventBuffers[conversationId], managedBuffer.allowsReplay else {
            return nil
        }
        let subscription = managedBuffer.buffer.subscribe(afterIndex: afterIndex)
        return AgentEventSubscription(
            generation: managedBuffer.generation,
            stream: subscription.stream
        )
    }

    /// Number of events currently buffered for a conversation (local count,
    /// subject to eviction — NOT the global event count). Not on the protocol —
    /// the VM tracks its own observed/persisted replay cursors. Useful for diagnostics.
    func retainedEventCount(conversationId: String) -> Int {
        eventBuffers[conversationId]?.buffer.retainedCount ?? 0
    }

    /// Notify the buffer that events up to `index` have been persisted to SwiftData,
    /// allowing eviction of old events to bound memory usage.
    func markPersisted(conversationId: String, generation: UUID, upTo index: Int) {
        guard let managedBuffer = eventBuffers[conversationId], managedBuffer.generation == generation else {
            return  // Stale trailing save from an older runtime generation.
        }
        managedBuffer.buffer.markPersisted(upTo: index)
        // If the process already exited and no VM is attached, a previous cleanup timer
        // may have deferred eviction while waiting for persistence to catch up. Re-arm a
        // short follow-up cleanup so the buffer does not become immortal after a later
        // successful save.
        if processes[conversationId] == nil,
           !managedBuffer.buffer.hasSubscribers,
           !managedBuffer.buffer.hasUnpersistedEvents {
            scheduleBufferCleanup(
                for: conversationId,
                generation: generation,
                delay: .seconds(30)
            )
        }
    }
```

---

Runtime teardown, stdin delivery, reconfigure, and process-exit cleanup continue in [Supplement: Agent Runtime Teardown and Reconfiguration](supplement-agent-runtime-teardown.md).

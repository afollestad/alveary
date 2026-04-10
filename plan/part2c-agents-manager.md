# Part 2c: Agent Process Management

Agent process spawning, DefaultAgentsManager actor, ConversationState, streaming pipeline. EventBuffer and agent lifecycle methods are in Part 2d. Continues from Part 2b.

## Implementation Status

- [x] `DefaultAgentsManager`, `AgentsManager`, `ConversationRuntimeStore`, `ConversationState`, and `SetupPhase` are implemented in the repo.
- [x] Spawn context preparation, process publication, stream task ownership, replayable buffer installation, and session-continuity notices are implemented.
- [x] Regression coverage exists at the runtime layer, including manager lifecycle coverage in `SkepTests/Services/AgentsManagerTests.swift`.
- [x] `ConversationViewModel` integration described later in this document is implemented in the repo and covered by focused VM/runtime regression tests.


## Agent Process Spawning

Agent CLIs are spawned as plain processes with **piped stdin/stdout/stderr** -- not PTYs. Each CLI is invoked in its structured JSON output mode, and the app reads JSON lines from stdout to drive a native chat UI. This approach has been validated by other desktop apps that interface with multiple agent CLIs via structured JSON output.

### Spawn Pipeline

```
  UI: "Start agent"
       │
       ▼
  ConversationViewModel.startAgent(config: AgentSpawnConfig)
       │
       ├──▶ ConversationViewModel.prepareForSpawn(...)
       │         → single preflight owner; runs ProviderSetupService
       │           before any direct call into AgentsManager.spawn(...)
       │
       ├──▶ ProviderSetupService.prepareForSpawn(providerId, workingDirectory, autoTrust)
       │         → best-effort trust/config setup before launch
       │
       ▼
  AgentsManager.spawn(id, config)
       │
       ├──▶ ProviderDetectionService.resolvedPath(for: providerId)
       │         → CLI path (e.g. /Users/you/.local/bin/claude)
       │         → throws AgentError.cliNotInstalled if missing
       │
       ├──▶ resolveAdapter(for: providerId)
       │         → ClaudeAdapter (or future provider adapter)
       │
       ├──▶ SessionManager.createEntry(id, cwd, providerId)
       │         → returns whether this binding may resume
       │
       ├──▶ SessionManager.sessionId(for: id)
       │         → persisted app/provider session identity
       │
       ├──▶ AgentSpawnConfig → AgentConfig conversion
       │         → adds sessionId from SessionManager
       │
       ├──▶ adapter.buildArgs(config: AgentConfig)
       │         → ["-p", "--output-format", "stream-json", ...]
       │
       ├──▶ adapter.sessionLaunch(sessionId:, cwd:, isResuming:, forkSession:)
       │         → args + continuity (`.preserved` or `.restartedFresh`)
       │
       ├──▶ AgentEnvironmentBuilder.buildEnvironment(providerEnv:)
       │         → filtered env dict (auth keys, PATH, TERM, ...)
       │
       ├──▶ Process() with piped stdin/stdout/stderr
       │         → process.run()
       │
       └──▶ readAgentOutput(stdout:, stderr:, adapter:)
                 → AsyncStream<ConversationEvent>
                       │
                       ▼
              ConversationViewModel subscribes
              → handleEvent() → SwiftData insert → UI update
```

### Structured Output Mode (Claude)

Reference: [CLI Reference](https://code.claude.com/docs/en/cli-reference) | [Hooks Guide](https://code.claude.com/docs/en/hooks-guide) | [Hooks Reference](https://code.claude.com/docs/en/hooks) | [Permission Modes](https://code.claude.com/docs/en/permission-modes)

The initial version uses Claude Code's **bidirectional JSON streaming** -- a single long-lived process that accepts user messages on stdin and streams structured events on stdout:

```
claude -p --output-format stream-json --input-format stream-json \
  --verbose --include-partial-messages \
  --session-id <uuid> --permission-mode default
```

The process stays alive across turns. User messages are sent as JSON lines to stdin; Claude streams structured JSON events to stdout for each turn. No re-spawn needed.

Key flags:
- `--input-format stream-json` -- accept user messages as JSON on stdin (enables multi-turn without re-spawn)
- `--output-format stream-json` (requires `--verbose`) -- structured JSON events on stdout
- `--include-partial-messages` -- emit `stream_event` lines wrapping the Messages API streaming protocol (`message_start`, `content_block_start`, `content_block_delta`, `content_block_stop`, `message_delta`, `message_stop`). Each `content_block_delta` carries a small text chunk. The complete `assistant` event still arrives at the end. Without this flag, the app only gets the full message after the entire response is generated, which means no visible typing indicator or progressive text rendering. **Required for a responsive chat UI.**
- `--session-id <uuid>` -- session isolation for multi-chat support
- `--permission-mode <mode>` -- set permission mode at spawn time (`plan`, `auto`, `default`, `acceptEdits`, `bypassPermissions`)

Additional flags the app may want to expose:
- `--add-dir <directories...>` -- grant tool access to additional directories beyond the cwd
- `--effort <level>` -- set effort level (`low`, `medium`, `high`, `max`)
- `--model <model>` -- override the model for the session
- `--fallback-model <model>` -- automatic fallback when default model is overloaded
- `--max-budget-usd <amount>` -- cap API spend for the session
- `--allowedTools` / `--disallowedTools` -- fine-grained tool access control
- `--mcp-config <configs...>` -- pass MCP server config directly (JSON files or strings)
- `--name` / `-n` -- set a display name for the session
- `--from-pr [value]` -- resume a session linked to a PR

Flags intentionally **not** exposed in v1:
- `--no-session-persistence` — conflicts with the validated resume / fork-session model by preventing the on-disk session artifact from being created.
- `--worktree` / `-w` — bypasses the app-owned `WorktreeManager`, which is responsible for thread metadata, rollback, and cleanup.
- `--fork-session` -- create a new session ID when resuming (branch the conversation)
- `--replay-user-messages` — not enabled in v1. Skep already persists outbound user messages before stdin delivery, and turning this on would require the documented dedupe guard in `ConversationViewModel.handleEvent()`.
- `--bare` -- minimal mode: skip hooks, LSP, plugin sync, auto-memory, and CLAUDE.md discovery

Note: The Claude CLI includes additional flags not listed above (e.g. `--agents`, `--from-pr`, `--tmux`, `--fallback-model`) that are not needed for the initial version. Run `claude --help` for the full list.

**Input message format** (verified by testing):
```json
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"your message here"}]}}
```

Claude's CLI handles all tool execution (file editing, bash commands, MCP, etc.) internally -- the app just gets a structured feed of what's happening.

**Future providers**: the adapter pattern keeps the chat rendering and persistence layers generic. Bidirectional providers follow Claude's long-lived process path. Providers that need one process per turn should keep replacement spawns in `AgentsManager`: the manager reuses the last successful `AgentSpawnConfig`, re-spawns with the next turn in `initialPrompt`, and re-registers process tracking before streaming output.

### Spawning via Process Pipes

The agent process is spawned by `AgentsManager.spawn()` (see **Actor for Agent Process Management** below for the full implementation). It creates a `Process` with piped stdin/stdout/stderr, sets the CLI path (from `ProviderDetectionService`), args (from the adapter), environment (from `AgentEnvironmentBuilder`), and working directory. Output is read line-by-line from stdout. **Do not close stdin** -- it stays open for the lifetime of the process to accept subsequent messages.

### Sending User Messages (Multi-Turn)

The process stays alive across turns. User messages are written as JSON lines to stdin by `ClaudeAdapter.sendMessage()` (see **ClaudeAdapter Implementation** in the Turn State section for the full code). The app calls `agentsManager.sendMessage(message, conversationId:)`, which delegates to the adapter.

Claude processes the turn (possibly multiple tool-use cycles), streams JSON events to stdout, and emits a `result` event when the turn is complete. The app then sends the next message. **Do not close stdin** -- the pipe must stay open for the process to accept subsequent messages.

### Building CLI Arguments

Each provider adapter builds the provider-owned portion of the argument list, while the manager appends launch-scoped session args and user customizations:

1. Structured output flag (`--output-format stream-json` or `--json`).
2. Session isolation args from the adapter's session strategy (`--session-id <uuid>` for Claude, or `--resume` for existing sessions when the provider can actually resume).
3. Permission mode flag: `--permission-mode <mode>` (e.g. `default`, `plan`, `bypassPermissions`). Verified by testing: `--permission-mode bypassPermissions` alone is sufficient -- `--dangerously-skip-permissions` is not needed alongside it.
4. Extra args from user's custom provider config.

### Environment

A minimal environment is built (not inheriting the parent environment wholesale):
- `HOME`, `USER`, `PATH`, `LANG`
- Agent auth vars from an allowlist (`ANTHROPIC_API_KEY`, etc.)
- Provider-specific env overrides from custom config

See the **Environment Variables** section for full details and Swift example.

### Actor for Agent Process Management

Agent interaction state must be thread-safe since data arrives on background threads. `AgentsManager` is the single entry point for all agent lifecycle operations.

### DefaultAgentsManager Internal Structure

```
DefaultAgentsManager (actor)
│
├── processes: [conversationId: Process]          ← live agent processes
├── adapters: [conversationId: AgentAdapter]      ← provider-specific decoder/sender
├── streamTasks: [conversationId: Task]           ← stdout reader tasks (one per process)
├── eventBuffers: [conversationId: ManagedEventBuffer] ← generation-scoped buffer + replay policy
├── stdinWriteTails: [conversationId: PendingStdinWrite] ← serializes detached stdin writes per conversation
├── suppressedExitPIDs: [conversationId: Set<pid>] ← expected exits keyed to the specific runtime PID they belong to
├── closingConversationIds: Set<String>           ← synchronous tombstones that reject new sends before async teardown runs
├── pendingSessionRemovalIds: Set<String>         ← destructive teardown removes session bindings only after child exit is confirmed
├── pendingSessionRemovalErrors: [String: String] ← durable session-removal failures captured for `destroyRuntime()` / archive-delete callers
│     └── ManagedEventBuffer (Sendable value)
│           ├── generation: UUID                  ← current runtime/buffer identity for this conversation
│           ├── allowsReplay: Bool                ← false for kill/archive durability-grace buffers
│           └── buffer: EventBuffer (@unchecked Sendable)
│                 ├── events: [ConversationEvent] ← ring buffer, evicts past persistedIndex
│                 ├── continuations: [UUID: Continuation]
│                 ├── baseOffset: Int             ← tracks evicted count for global indexing
│                 └── persistedIndex: Int         ← set by VM after modelContext.save()
│
├── conversationStatesStore: OSAllocatedUnfairLock<[String: ConversationState]>
│     └── ConversationState (@MainActor @Observable)
│           ├── turnState: TurnState              ← is the agent busy?
│           ├── messageQueue: MessageQueue         ← queued messages for next turn
│           ├── streamingText: String?             ← live text from messageChunk events
│           ├── lastTurnError: String?             ← setup/send/respawn failure banner text
│           ├── inputDraft: String                 ← survives VM destruction in current app session
│           ├── selectedModel: String?             ← model picker state (nil = CLI default)
│           ├── grouper: ChatItemGrouper           ← incremental event → ChatItem cache
│           ├── stagedContext: String?              ← prepended to next message
│           ├── sessionContinuityNotice: String?   ← inline warning when local history is preserved but provider context restarted fresh
│           ├── isSendingMessage: Bool             ← closes MainActor reentrancy while setup/respawn/stdin write is in flight
│           ├── isReconfiguringSession: Bool        ← disables composer while fork-session is in flight
│           ├── lastObservedEventIndex: Int         ← latest EventBuffer index consumed by this VM
│           ├── lastPersistedEventIndex: Int        ← last durable replay boundary for reconnects
│           ├── activeBufferGeneration: UUID?      ← last subscribed runtime generation; save-task uses it for markPersisted
│           ├── activeSubscriptionToken: UUID?     ← cancels stale replay/EOF cleanup after re-subscribe or VM replacement
│           ├── showPermissionBanner: Bool          ← inline permission-denial banner visibility
│           ├── inFlightQueuedMessageID: UUID?     ← queued head currently being auto-sent; prevents stale dismiss/send races
│           ├── respawnAttempts: Int               ← crash guard counter
│           ├── lastPermissionDeniedToolNames: Set<String> ← latest turn's denied tool names for banner CTA gating
│           └── setupPhase: SetupPhase?            ← thread setup progress (first-message flow)
│
├── processSnapshot: OSAllocatedUnfairLock<[Process]>     ← for synchronous shutdown
├── statusSnapshot: OSAllocatedUnfairLock<[String: ActivitySignal]>  ← for sidebar
│
├── Injected dependencies:
│     ├── sessionManager: SessionManager
│     ├── providerDetection: ProviderDetectionService
│     ├── environmentBuilder: AgentEnvironmentBuilder
│     ├── providerRegistry: ProviderRegistry
│     ├── settingsService: SettingsService
│     └── notificationManager: NotificationManager
│
└── StderrBuffer (per-process, inside readAgentOutput)
      └── Circular buffer of last 20 stderr lines for error reporting
```

Ownership rules:
- **EventBuffer** outlives the process only for replayable crash/EOF recovery or explicit durability grace. The `ManagedEventBuffer.generation` ties saves, status updates, and replay to the correct runtime, and `allowsReplay = false` prevents kill/archive grace buffers from masquerading as live replay state.
- **ConversationState** outlives the EventBuffer within a running app session (removed by `kill()`, preserved across `reconfigureSession()`, and discarded when the app process terminates)
- **Process** is the shortest-lived — removed on exit, kill, or reconfigure
- **Session bindings** remain durable until destructive teardown confirms the old child is gone; `destroyRuntime(conversationId:)` is the single public owner of that sequence so archive/delete/rollback do not drift from the runtime's teardown order
- Lock-protected snapshots are updated whenever `processes` or `statusSnapshot` change

`ConversationState` intentionally mixes three categories of state: live composer UI (`inputDraft`, staged context, permission banner), replay/durability bookkeeping (`lastObservedEventIndex`, `lastPersistedEventIndex`, `activeBufferGeneration`, `activeSubscriptionToken`), and per-session recovery guards (`respawnAttempts`, `inFlightQueuedMessageID`, `setupPhase`). Calling those out here keeps later ViewModel and permission docs from introducing fields that seem to appear "out of nowhere."

```swift
@MainActor @Observable
final class ConversationState {  // Skep/Services/Agent/ConversationState.swift
    let messageQueue = MessageQueue()
    var turnState = TurnState()
    /// Accumulated top-level streaming text.
    var streamingText: String?
    var lastTurnError: String?
    var stagedContext: String?
    /// Visible warning when Skep kept local history but the provider had to start fresh.
    var sessionContinuityNotice: String?
    /// MainActor gate for async send/setup/respawn preflight.
    var isSendingMessage: Bool = false
    /// Set while fork-session teardown + re-spawn is in flight.
    var isReconfiguringSession: Bool = false
    /// Global consumed-event count, including transient non-persisted events.
    var lastObservedEventIndex: Int = 0
    /// Durable replay cursor; advances only after a successful save.
    var lastPersistedEventIndex: Int = 0
    /// Current EventBuffer generation for save-task generation checks.
    var activeBufferGeneration: UUID?
    /// Current subscription token; stale tasks must not outlive it.
    var activeSubscriptionToken: UUID?
    /// Input draft for the current app launch.
    var inputDraft: String = ""
    /// Launch-scoped model override; `nil` means CLI default.
    var selectedModel: String?
    /// Cached grouped history for reconnects.
    var grouper = ChatItemGrouper()
    /// Survives VM destruction so respawn caps cannot be bypassed by navigation.
    var respawnAttempts: Int = 0
    /// Drives the inline permission-denial banner.
    var showPermissionBanner: Bool = false
    /// Latest denied tool names for permission-banner CTA gating.
    var lastPermissionDeniedToolNames: Set<String> = []
    /// Queue head currently committed to the auto-send path.
    var inFlightQueuedMessageID: UUID?
    /// First-message setup progress for the empty-thread UI.
    var setupPhase: SetupPhase?

    func appendStreamingChunk(_ text: String) {
        if streamingText == nil {
            streamingText = text
        } else {
            streamingText?.append(text)
        }
    }

    func clearStreamingText() {
        streamingText = nil
    }
}

/// Separate from `AgentsManager` so chat/view-model code does not depend on a concrete
/// `ConversationState` through the transport/lifecycle protocol boundary.
protocol ConversationRuntimeStore {  // Skep/Services/Agent/ConversationRuntimeStore.swift
    @MainActor func conversationState(for conversationId: String) -> ConversationState
}

/// Production resolves both protocols to the same `DefaultAgentsManager` instance.
/// Tests can do the same with `MockAgentsManager`, or supply a separate runtime-store mock.

/// Test boundary: `MockAgentsManager` conforms here in unit tests.
protocol AgentsManager: Actor {  // Skep/Services/Agent/AgentsManager.swift
    func spawn(id: String, config: AgentSpawnConfig, forkSession: Bool) async throws  // default provided via protocol extension below
    func subscribe(conversationId: String, afterIndex: Int) -> AgentEventSubscription?
    func sendMessage(_ message: String, conversationId: String) async throws
    func cancelTurn(conversationId: String)
    /// Single public owner for destructive teardown paths (archive/delete/first-run rollback).
    /// Waits for the runtime to be gone and for the manager-owned session-binding removal
    /// to finish, so callers do not duplicate `SessionManager` cleanup out-of-band.
    func destroyRuntime(conversationId: String) async throws
    func kill(conversationId: String)
    func killAll()
    /// Lifecycle-aware: returns true while a child process is live OR while a spawn for
    /// this conversation is still in flight. Archive/delete use this to avoid treating a
    /// spawn-race window as dormant before the deferred kill/teardown finishes.
    func isRunning(conversationId: String) -> Bool
    /// Returns true only when a child has been published into `processes`. Startup
    /// orphan cleanup uses this narrower check instead of `isRunning()` so an in-flight
    /// spawn does not mask a real orphan from a prior launch.
    func hasTrackedProcess(conversationId: String) -> Bool
    /// Returns true while spawn/reconfigure bookkeeping exists for the conversation even
    /// if no child has been published yet. Startup orphan cleanup treats this as an
    /// ambiguous current-launch state and skips termination rather than risking a false kill.
    func hasInflightLifecycle(conversationId: String) -> Bool
    func reconfigureSession(conversationId: String, config: AgentSpawnConfig) async throws
    func markPersisted(conversationId: String, generation: UUID, upTo index: Int)
    nonisolated func status(for conversationId: String) -> ActivitySignal
    nonisolated var allStatuses: [String: ActivitySignal] { get }
    /// Marks app shutdown so new spawns are rejected and an in-flight spawn that
    /// finishes late tears its child down before it can be orphaned.
    /// Nonisolated so `applicationWillTerminate` can call it synchronously.
    nonisolated func beginShutdown()
    /// Synchronous snapshot of all active processes for shutdown cleanup.
    /// Nonisolated so `applicationWillTerminate` (synchronous) can read it.
    nonisolated var allProcessesSnapshot: [Process] { get }
}

/// Protocol extension to provide a default value for `forkSession`. Swift protocols
/// cannot have default parameter values; this extension provides the ergonomic
/// `spawn(id:config:)` overload that callers like `ConversationViewModel.startAgent()` use.
extension AgentsManager {
    func spawn(id: String, config: AgentSpawnConfig) async throws {
        try await spawn(id: id, config: config, forkSession: false)
    }
}

actor DefaultAgentsManager: AgentsManager, ConversationRuntimeStore {  // Skep/Services/Agent/DefaultAgentsManager.swift
    private var processes: [String: Process] = [:]
    private var adapters: [String: AgentAdapter] = [:]
    private var streamTasks: [String: Task<Void, Never>] = [:]
    private var eventBuffers: [String: ManagedEventBuffer] = [:]
    /// Serializes physical stdin writes per conversation.
    private var stdinWriteTails: [String: PendingStdinWrite] = [:]
    /// Expected exits keyed by runtime PID so replacement processes stay reportable.
    private var suppressedExitPIDs: [String: Set<Int32>] = [:]
    /// Synchronous tombstone so late sends fail before async teardown finishes.
    private var closingConversationIds: Set<String> = []
    /// Session bindings removed only after the old runtime is definitely gone.
    private var pendingSessionRemovalIds: Set<String> = []
    /// Durable session-removal failures surfaced back through `destroyRuntime()`.
    private var pendingSessionRemovalErrors: [String: String] = [:]
    /// Guard against concurrent spawn/kill interleaving for one conversation.
    private var spawningIds: Set<String> = []
    /// IDs currently in the fork-session teardown → re-spawn window.
    private var reconfiguringIds: Set<String> = []
    /// Deferred kills that must win over an in-flight spawn or reconfigure.
    private var pendingKillIds: Set<String> = []
    /// Synchronous shutdown tombstone checked before and after `process.run()`.
    private let shutdownRequested = OSAllocatedUnfairLock(initialState: false)
    private let sessionManager: SessionManager
    private let providerDetection: ProviderDetectionService
    private let environmentBuilder: AgentEnvironmentBuilder
    private let providerRegistry: ProviderRegistry
    private let settingsService: SettingsService
    private let notificationManager: NotificationManager

    /// Lock-protected store of launch-scoped per-conversation UI/runtime state.
    private let conversationStatesStore = OSAllocatedUnfairLock(initialState: [String: ConversationState]())

    /// Synchronous lookup/create for the shared launch-scoped `ConversationState`.
    @MainActor func conversationState(for conversationId: String) -> ConversationState {
        // Atomic check-and-create prevents duplicate state objects.
        conversationStatesStore.withLock { store in
            if let existing = store[conversationId] {
                return existing
            }
            let state = ConversationState()
            store[conversationId] = state
            return state
        }
    }

    nonisolated func beginShutdown() {
        shutdownRequested.withLock { $0 = true }
    }

    // EventBuffer class and agent lifecycle methods (spawn(), kill(), subscribe(),
    // sendMessage(), reconfigureSession(), etc.) are in
    // Part 2d: EventBuffer and Agent Lifecycle (plan/part2d-spawn-and-buffer.md).

    private func resolveAdapter(for providerId: String) -> AgentAdapter {
        // For v1, only Claude is supported. Future providers add cases here.
        // ClaudeAdapter is implemented in Turn State and Event Lifecycle (later in this Part).
        // Stub this with fatalError("TODO: ClaudeAdapter") during initial AgentsManager build,
        // then replace when ClaudeAdapter is implemented.
        switch providerId {
        case "claude": return ClaudeAdapter()
        default: fatalError("Unknown provider: \(providerId). Add an adapter case for this provider.")
        }
    }

    /// Thread-safe circular buffer for recent stderr lines.
    /// Used for stream-read / decode failure context while stderr is drained in
    /// parallel to avoid pipe deadlock.
    private final class StderrBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer: [String]
        private var writeIndex: Int = 0
        private var isFull: Bool = false
        private let capacity: Int

        init(maxLines: Int) {
            self.capacity = maxLines
            self.buffer = []
            self.buffer.reserveCapacity(maxLines)
        }

        func append(_ line: String) {
            lock.lock()
            defer { lock.unlock() }
            if buffer.count < capacity {
                buffer.append(line)
            } else {
                buffer[writeIndex] = line
                isFull = true
            }
            writeIndex = (writeIndex + 1) % capacity
        }

        /// Returns lines in chronological order.
        var lastLines: [String] {
            lock.lock()
            defer { lock.unlock() }
            if !isFull { return buffer }
            // Circular: oldest is at writeIndex, wrap around
            return Array(buffer[writeIndex...]) + Array(buffer[..<writeIndex])
        }
    }

    private func readAgentOutput(stdout: FileHandle, stderr: FileHandle, adapter: AgentAdapter) -> AsyncStream<ConversationEvent> {
        // FileHandle is not Sendable, but these handles are exclusively owned by this
        // stream — the actor won't access them again after handing them off.
        nonisolated(unsafe) let stdout = stdout
        nonisolated(unsafe) let stderr = stderr
        return AsyncStream { continuation in
            // Read stderr in parallel to prevent pipe buffer deadlock.
            // Capture recent lines for stream-read failure context.
            let stderrBuffer = StderrBuffer(maxLines: 20)
            let stderrTask = Task.detached {
                do {
                    for try await line in stderr.bytes.lines {
                        stderrBuffer.append(line)
                    }
                } catch { /* stderr closed — expected on normal exit */ }
            }
            Task.detached { [stderrBuffer] in
                do {
                    for try await line in stdout.bytes.lines {
                        guard let data = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else {
                            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { continue }
                            let prefix = String(trimmed.prefix(240))
                            let stderrTail = stderrBuffer.lastLines.joined(separator: "\n")
                            let message = stderrTail.isEmpty
                                ? "Malformed agent stdout line: \(prefix)"
                                : "Malformed agent stdout line: \(prefix)\n\nStderr:\n\(stderrTail)"
                            continuation.yield(.error(message: message))
                            break
                        }
                        for event in adapter.decode(json) {
                            continuation.yield(event)
                        }
                    }
                } catch {
                    let stderrTail = stderrBuffer.lastLines.joined(separator: "\n")
                    let message = stderrTail.isEmpty
                        ? "Stream read failed: \(error.localizedDescription)"
                        : "Agent error: \(stderrTail)"
                    continuation.yield(.error(message: message))
                }
                // Let stderr drain to EOF instead of canceling it on stdout completion.
                // This avoids dropping the final stderr tail during fast shutdown paths
                // and keeps pipe ownership symmetrical.
                _ = await stderrTask.result
                for event in adapter.finalize() { continuation.yield(event) }
                continuation.finish()
            }
        }
    }
}
```

`ProviderDetectionService` is injected via Knit. It runs `claude --version` at startup, resolves the executable path (e.g. `/Users/you/.local/bin/claude`), and caches it. `AgentsManager.spawn()` reads the cached path, but if the provider has not been checked yet it performs an on-demand `checkProvider()` before failing so startup timing does not produce a false "not installed" state.

This is resolved via Knit as a protocol, so tests can inject a `MockAgentsManager` that returns canned event streams without spawning real processes.

**Unit tests for AgentsManager** (inject `MockAgentAdapter`, `MockProviderDetectionService`, `InMemorySessionManager`, `MockNotificationManager`, `MockAgentEnvironmentBuilder`, `InMemorySettingsService`): cover all public methods with standard happy-path and error tests. Non-obvious:
- `spawn()` throws `.spawnFailed` when a spawn is already in-flight for the same conversation ID; allows concurrent spawns for different IDs
- `spawn()` also throws when a live process already exists for that conversation ID; replacement is only legal through `reconfigureSession()` after awaited teardown
- Public `spawn()` also throws when `reconfigureSession()` is already in flight for that conversation ID, so a plain spawn cannot interleave into the fork-session gap; `reconfigureSession()` itself uses a private replacement-spawn helper that bypasses only that one guard
- `spawn()` wraps `process.run()` failures as `AgentError.spawnFailed` after re-running provider detection
- `spawn()` clears the in-flight guard on both success and failure (defer path)
- `spawn()` treats `ProviderCustomConfig.cli` with a slash as an explicit path, but re-resolves named custom commands through `ProviderDetectionService` instead of passing the raw command string straight into `Process.executableURL`
- `beginShutdown()` makes later `spawn()` calls fail fast, and a child launched in the shutdown window is torn down by the pre-publication or immediate post-publication re-check before it can be orphaned
- A child that exits before startup finishes still triggers cleanup via the immediate post-handler `process.isRunning` reconciliation path
- `spawn()` closes the parent's unused pipe ends immediately after `process.run()`, leaving only the stdin writer plus stdout/stderr readers open so EOF and teardown semantics are not extended by extra parent-held descriptors
- `kill()` marks the conversation as closing immediately, so late `sendMessage()` calls fail before async teardown has removed the runtime dictionaries
- `kill()` defers to `pendingKillIds` when a spawn is in-flight; deferred kill is honored before the spawn publishes status/buffer state or sends `initialPrompt`, and unpublished children are terminated locally before the defer cleanup runs
- `kill()` during `reconfigureSession()` lands in the same `pendingKillIds` path, aborts the replacement spawn before it begins, and removes the session/state instead of resurrecting the conversation after archive/delete
- `killAll()` snapshots published children plus `spawningIds` / `reconfiguringIds`, so conversations that only exist in lifecycle bookkeeping still get marked for deferred teardown
- `isRunning()` stays true while a spawn or reconfigure is still in-flight for that conversation, so archive/delete cannot race a late child launch or a fork-session gap
- `hasTrackedProcess()` is false while a spawn is only in bookkeeping state, and `hasInflightLifecycle()` is true for that same window so startup orphan cleanup can prefer false negatives over killing the current launch's child
- `destroyRuntime()` is the single destructive teardown owner for archive/delete/rollback: it waits for the runtime to disappear and for manager-owned session-binding removal to finish before returning
- `kill()` / `reconfigureSession()` suppress only the targeted PID's later `handleProcessExit()` status update, so explicit teardown does not resurrect `.stopped` / `.error` after the caller removed or replaced the status entry, while a replacement PID can still surface its own crash; `kill()` also posts a reactive status-clear notification immediately
- A stale old-PID termination handler still consumes its own suppression token on the early-return path, so that token cannot leak forward and accidentally suppress a future real exit if the OS later reuses the PID
- `spawn()` sets status to `.idle` for a fresh long-lived process with no immediate turn, and to `.busy` only when `initialPrompt` starts work immediately
- `spawn()` updates `ConversationState.sessionContinuityNotice`: clear it on preserved resume/fresh first launch, set it only when the adapter had to abandon `--resume` and restart fresh under otherwise preserved local history
- `spawn()` with a non-empty `initialPrompt` delivers that first turn through the same serialized `sendMessage()` path as later user messages and begins `ConversationState.turnState` up front; if the initial write fails, the fresh process is torn down, the manager-owned busy state is cleared immediately, and the spawn fails
- Successful `.tokens` events suppress the plain completion notification when a queued head is about to auto-send immediately, so users do not get a false "done" signal between queued turns
- Canceling `kill()` / `reconfigureSession()` while a stdin write is queued cancels both the queued tail task and any already-launched writer task recorded in `PendingStdinWrite`; once the blocking `write(contentsOf:)` itself has started, cancellation is only best-effort and the old process may still consume bytes until it exits
- `cancelTurn()` is a no-op when the process has already exited (no stale PID signal)
- `reconfigureSession()` old process termination handler is a no-op (stale PID guard)
- `reconfigureSession()` spawn failure preserves the current in-memory ConversationState (message queue, input draft, grouper are not lost) and sets `.error` status
- `scheduleBufferCleanup()` does NOT remove ConversationState (only EventBuffer)
- `scheduleBufferCleanup()` only evicts the same buffer generation that scheduled the cleanup; a later replacement buffer for the same conversation gets its own grace period
- `scheduleBufferCleanup()` skips buffers that still have unpersisted events, and `markPersisted(generation:upTo:)` re-arms cleanup after persistence catches up, so a failed save cannot silently discard the only replayable copy or leave the buffer orphaned forever
- `teardownProcess()` calls `finishAll()` on the EventBuffer before removing it (subscriber continuations must be finished to prevent VMs from hanging)
- `teardownProcess()` preserves the current in-memory ConversationState and status while removing process, adapter, streamTask, eventBuffer
- `handleProcessExit()` skips cleanup when the stored process PID doesn't match (stale termination handler guard)
- Stream reader drains stderr to EOF instead of canceling it when stdout finishes, so fast shutdown does not drop the final stderr tail or leave the read-side ownership ambiguous
- Stream reader calls `buffer.finishAll()` on stdout EOF; process crash without `result` event ends VM's `for await` via `finishAll()` and safety-net `endTurn()` runs
- Malformed non-empty stdout JSON surfaces a `.error` event with the raw-line prefix + stderr tail instead of being silently dropped as if the turn were still healthy
- `sendMessage()` serializes detached stdin writes per conversation, rejects conversations that are already closing/shutting down before launching a new detached writer, and does not set status to `.busy` if the process was killed or replaced during the write (PID + generation guard against stale status)

**Unit tests for EventBuffer:** cover push, subscribe, replay, unsubscribe, eviction, and finish lifecycle. Non-obvious:
- Events pushed between snapshot and registration are caught by the missed-event check (no dropped events during race)
- Eviction after `baseOffset > 0` correctly translates global `persistedIndex` to local count (does not over-evict unpersisted events)
- `subscribe(afterIndex:)` after eviction correctly translates global index to local via `baseOffset` (no skip or duplicate)
- `finishAll()` sets `isFinished` flag so late subscribers are immediately finished after replay (no hang)
- `push()` after `finishAll()` is ignored entirely (late stream-reader races after explicit teardown cannot leak stray events into replay or durability-grace buffers)
- `subscribe()` after `finishAll()` replays then immediately finishes the continuation

**Unit tests for StderrBuffer:** cover append, retrieval, and capacity. Non-obvious:
- `lastLines` returns lines in chronological order after wrapping (circular buffer correctness)

**Unit tests for ConversationEvent.toRecord():** cover all enum cases produce the correct record type and fields. Non-obvious:
- `.messageChunk` returns nil (stream-only event, never persisted)
- `.subAgentStarted`, `.subAgentProgress`, `.subAgentCompleted` return nil (control events, never persisted)

---

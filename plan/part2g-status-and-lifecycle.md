# Part 2g: Agent Status and Lifecycle

Reactive agent status for the sidebar, stopping/interrupting agents, agent lifecycle detection. Continues from Part 2f.

Phase note: the `DefaultAgentsManager` status storage, notifications, and process snapshots in this section are implemented alongside Phase 3 step #9 because the runtime and shutdown flow depend on them there. The `SidebarViewModel` observation wiring that consumes those signals lands later in Phase 6 / Part 4b.

## Reactive Agent Status for the Sidebar

`ActivitySignal` is defined in Part 2a (see **Activity Classification**). This section documents how `AgentsManager` exposes status to the sidebar and how the sidebar **observes** changes.

### Reading Status (Synchronous)

`AgentsManager` maintains a lock-protected status dictionary that the sidebar reads synchronously — no async calls or polling needed. Status updates are pushed when `spawn()` establishes the initial `.idle` / `.busy` state, when a successful stdin write flips an already-running conversation from `.idle` to `.busy`, when the stream reader receives `.tokens` (turn complete) or `.error`, when a process exits, and when explicit teardown removes a status entry entirely.

This status is intentionally **transport/runtime state**, not the full user-visible thread state. During queued auto-send handoff, the manager may transiently observe a successful `.tokens` before the next queued stdin write starts, but open-chat/UI consumers should continue treating the thread as effectively busy until `ConversationState.turnState`, `messageQueue`, and `inFlightQueuedMessageID` say otherwise. Part 4's `ThreadStatus` derivation should therefore combine manager status with launch-scoped queue state instead of treating `.idle` as a universal "done" signal.

### Observing Status Changes (SwiftUI Reactivity)

The lock-protected `statusSnapshot` is not `@Observable` — SwiftUI cannot observe it directly. To trigger sidebar re-rendering when agent status changes or a status entry is removed, `AgentsManager` posts a `Notification` from both `updateStatus()` and `clearStatus(for:)`, and `SidebarViewModel` observes it via a version counter. Process-lifecycle consumers use a separate notification because expected exits (`kill()` / `reconfigureSession()`) can remove the last live process without adding a new visible status:

```swift
// In DefaultAgentsManager:
extension Notification.Name {
    static let agentStatusChanged = Notification.Name("agentStatusChanged")
    static let managedProcessesChanged = Notification.Name("managedProcessesChanged")
}

private func updateStatus(_ signal: ActivitySignal, for id: String) {
    statusSnapshot.withLock { $0[id] = signal }
    // Post on MainActor so UI observers receive the notification on the main actor.
    // Include both the signal and conversation ID in userInfo so observers
    // (e.g. DiffViewerViewModel) can filter to the currently selected thread.
    Task { @MainActor in
        NotificationCenter.default.post(
            name: .agentStatusChanged,
            object: nil,
            userInfo: ["conversationId": id, "signal": signal]
        )
    }
}

private func clearStatus(for id: String) {
    statusSnapshot.withLock { $0.removeValue(forKey: id) }
    Task { @MainActor in
        NotificationCenter.default.post(
            name: .agentStatusChanged,
            object: nil,
            userInfo: ["conversationId": id, "signal": ActivitySignal.neutral]
        )
    }
}
```

Treat `.agentStatusChanged` as an **invalidation hint**, not the source of truth for consumers that are sensitive to ordering. Notifications are posted via separate main-actor tasks, so a later status write can overtake an earlier notification. Observers such as the diff viewer should re-read authoritative manager state (`status(for:)` or `hasTrackedProcess(conversationId:)`) before acting on a non-busy payload.

`SidebarViewModel` and `DiffViewerViewModel` observe `.agentStatusChanged` because they care about visible chat/activity state. `AppDelegate` observes `.managedProcessesChanged` instead when recalculating sudden-termination policy, because that policy follows the live-process snapshot rather than the status dictionary.

```swift
// In SidebarViewModel (full implementation in Part 4b):
@MainActor @Observable
class SidebarViewModel {
    /// Incremented on every agent status change. SidebarView reads this to
    /// create an @Observable dependency — when it changes, the view re-evaluates,
    /// calling threadStatus(for:) which reads the latest lock-protected status.
    private(set) var statusVersion: Int = 0
    private var statusObserver: NSObjectProtocol?

    init(agentsManager: any AgentsManager, modelContext: ModelContext,
         shell: ShellRunner, gitHubCLI: GitHubCLIService,
         worktreeManager: WorktreeManager, settingsService: SettingsService) {
        // ... store all dependencies ...
        statusObserver = NotificationCenter.default.addObserver(
            forName: .agentStatusChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.statusVersion += 1
        }
    }

    deinit {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
    }
```

```swift
// In SidebarView (inside body):
// Touch the version counter to observe status changes.
let _ = viewModel.statusVersion
```

This bridges the lock-protected status (fast synchronous reads) with SwiftUI's observation system (automatic re-rendering). The notification carries both `conversationId` and `signal` in `userInfo`, but the sidebar ignores them — just bumping the counter is enough to trigger re-rendering.

```swift
// Inside DefaultAgentsManager (actor) — lock-protected, nonisolated for synchronous sidebar access.
private let statusSnapshot = OSAllocatedUnfairLock(initialState: [String: ActivitySignal]())

nonisolated func status(for conversationId: String) -> ActivitySignal {
    statusSnapshot.withLock { $0[conversationId] ?? .neutral }
}

nonisolated var allStatuses: [String: ActivitySignal] {
    statusSnapshot.withLock { $0 }
}

// updateStatus() — same implementation as shown in the notification section above.
```

Status is updated at these points:
- **`spawn()`** → `.idle` when the long-lived process is ready and waiting for input, or `.busy` only when the spawn path also starts an immediate turn (`initialPrompt`)
- **`sendMessage()` success** → `.busy` once the stdin write completes for a currently running conversation
- **Stream reader receives `.tokens`** → `.idle` (transport turn complete) or `.error` (if `isError`). Completion UX and OS notifications should still suppress a plain "done" state when a queued head will auto-send immediately.
- **Stream reader receives `.error`** → `.error` (stream read / adapter failure)
- **`handleProcessExit()`** → `.error` for non-zero / signaled exits, `.stopped` only for clean exits that did not already end in `.idle` or `.error`. Unexpected exits also populate `ConversationState.lastTurnError` with a generic crash banner when no more specific turn error already exists. Expected exits requested by `kill()` / `reconfigureSession()` are suppressed with PID-scoped tokens so they do not re-add status after explicit teardown, while a replacement runtime can still report its own failure.
- **`reconfigureSession()`** → teardown (no status change), then `spawn()` restores `.idle` or `.busy` using the same immediate-turn rule as a normal spawn. On spawn failure: `.error` + `lastTurnError` set.
- **`kill()`** → `clearStatus(for:)` removes the entry immediately and posts the same sidebar invalidation path used for visible status changes; the later expected termination handler is suppressed so it cannot resurrect `.stopped` / `.error`

The `SidebarViewModel` reads `agentsManager.status(for:)` (lock-protected, nonisolated) to derive `ThreadStatus` for each thread without calling async functions during rendering. The full `threadStatus(for:)` implementation is in [Part 4b: Sidebar](part4b-sidebar.md).

---

## Stopping and Interrupting

The app stopping an agent and the agent finishing a turn are separate concepts. In v1 Claude, turn completion comes from the standard `result` event; there is no separate hook/event channel for `idle_prompt`-style notifications in `-p` mode.

### Stopping Agents

Agent runtimes are spawned as child processes, so the app can:

1. **Send SIGINT** -- `kill(process.processIdentifier, SIGINT)` sends the interrupt signal (equivalent to Ctrl+C). The agent handles graceful cancellation.
2. **Send SIGTERM** -- `process.terminate()` for graceful shutdown. Follow with SIGKILL after a timeout (e.g. 5 seconds) if the process doesn't exit.
3. **Do not close stdin explicitly** -- let the process exit close the pipe. This avoids a cross-thread `close` + `write(contentsOf:)` race on `FileHandle`.

### Learning an Agent Stopped

**From structured events**: the `result` event with `stop_reason: "end_turn"` signals turn completion. The `result` event with `is_error: true` signals a failed turn.

**From process exit**: `process.terminationStatus` is available after the process exits. Non-zero indicates an error. The stdout `AsyncStream` finishes when the process exits.

### Summary (Claude)

| Mechanism | How |
|---|---|
| App stops agent | `process.terminate()` (SIGTERM), then SIGKILL after timeout |
| App interrupts turn | `kill(pid, SIGINT)` |
| Agent signals "done working" | `result` event with `stop_reason: "end_turn"` |
| Agent signals "turn failed" | `result` event with `is_error: true` |
| Stream/adapter failure | stream `.error` event |
| App detects process exit | `process.terminationStatus` |

---

## Agent Lifecycle Detection

Reference: [Hooks Guide](https://code.claude.com/docs/en/hooks-guide) | [Hooks Reference](https://code.claude.com/docs/en/hooks) | [CLI Reference](https://code.claude.com/docs/en/cli-reference)

The app detects agent state entirely from the standard event stream. No separate hook mechanism is needed.

**Validated**: `--include-hook-events` was tested and does not produce any events in `-p` mode (CLI v2.1.92). The flag has been removed from the spawn args.

**Approach**: the app relies on the standard event stream for all state detection (see table below). The `ConversationEvent` enum retains `.notification` and `.stop` cases as reserved for potential future use.

### How the App Detects Agent State

| State | Signal | Source |
|---|---|---|
| **Turn complete (idle)** | `result` event with `stop_reason: "end_turn"` | Always present |
| **Turn failed** | `result` event with `is_error: true` | Always present |
| **Stream/adapter failure** | stream `.error` event | Event decoding / pipe read failure |
| **Permission denied** | `result` event with non-empty `permission_denials` array (structured, no string matching) | In `default` mode when non-interactive |
| **Agent crashed** | stdout `AsyncStream` finishes + `process.terminationStatus != 0` | Process lifecycle |
| **Tool in progress** | `assistant` event with `tool_use` content block, no matching `tool_result` yet | Standard event flow |
| **Sub-agent started** | `system/task_started` event with `tool_use_id` | Always present when sub-agent spawned |
| **Sub-agent progress** | `system/task_progress` event with `last_tool_name`, `tool_uses` count | Periodic during sub-agent execution |
| **Sub-agent completed** | `system/task_notification` event with `status: "completed"` | Always present when sub-agent finishes |
| **Streaming text** | `stream_event` with `content_block_delta` | With `--include-partial-messages` |

These signals drive OS notifications (when the app isn't focused) and the agent status indicator in the sidebar.

```
  Agent stdout JSON stream
       │
       ▼
  ClaudeAdapter.decode()
       │
       ▼
  AgentsManager stream reader task   (service layer — always running)
       │
       ├──▶ EventBuffer.push(event)
       │
       ├──▶ updateStatus()           (on .tokens/.error/process-exit; sidebar reads via lock)
       │
       ├──▶ NotificationManager.handleEvent()
       │         │
       │         ├── App focused?
       │         │     YES → play in-app chime
       │         │     NO  → post OS notification
       │
       └──▶ ConversationViewModel.handleEvent()   (subscribed when VM exists)
                │
                ├── .messageChunk       →  accumulate streamingText (live UI, not persisted)
                ├── .subAgent*          →  grouper.handleSubAgentControl() (live UI, not persisted)
                ├── .message            →  SwiftData insert → Chat UI
                ├── .toolCall/Result    →  SwiftData insert → Working block
                ├── .thinking           →  SwiftData insert → Thinking block
                ├── .tokens (result)    →  handleTurnCompleted()
                │                              │
                │                              ├──▶ No queued follow-up → endTurn()
                │                              └──▶ Queued follow-up → keep busy until next send succeeds/fails
                │
                └── .error              →  SwiftData insert → Error banner
```

**Future providers** that don't support in-stream events would need a fallback HTTP hook server (e.g. Vapor on an ephemeral port). The adapter pattern encapsulates this.

### OS Notifications

When the agent needs attention (turn complete, error) and the app isn't focused, post an OS notification via `UNUserNotificationCenter` (see the Swift example in **App Settings > Notification Settings**).

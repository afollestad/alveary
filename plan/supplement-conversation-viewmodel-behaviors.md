# Supplement: ConversationViewModel Behaviors

`SetupPhase`, auto-naming helpers, staged-context UI, and outbound routing rules that support `ConversationViewModel`. Continues from [Part 2f: ViewModel](part2f-viewmodel.md).

## Implementation Status

- [x] The standalone `SetupPhase` runtime type used by `ConversationState` is implemented in `Skep/Utilities/SetupPhase.swift`.
- [x] `ConversationViewModel` itself and the behavior in this supplement are implemented in the repo for Phase 3 step #13.
- [x] The save/replay, setup rollback, queued-send, and prompt-answer rules documented here are wired in the runtime layer.

**Used by**: `ConversationView` → `ChatView` (middle pane when a thread is selected).

**Unit tests for ConversationViewModel** (inject `MockAgentsManager`, using that same mock as `ConversationRuntimeStore` too unless a dedicated `MockConversationRuntimeStore` is clearer, plus `MockWorktreeManager`, `MockProviderSetupService`, in-memory `ModelContext`, `InMemorySettingsService`): cover all public methods (`send`, `queueOrSend`, `setupAndStart`, `retryNextQueuedMessage`, `steer`, `cancel`, `reconfigureSession`, `startAgent`) and `handleEvent` routing. Non-obvious:
- **Outbound reservation**: `withOutboundReservation()` flips `state.isSendingMessage` before the first `await` in setup/respawn/stdin-write flows; a second `queueOrSend()` while that reservation is held must queue instead of double-sending, and `answerPrompt()` must throw instead of racing through the same gap
- **Send ordering**: `send()` must NOT insert a SwiftData record when `agentsManager.sendMessage()` throws; `turnState.isActive` is set only after the transport write succeeds, and remains active even if the subsequent `modelContext.save()` fails
- **Outbound message durability**: successful `send()` / `steer()` schedule the same coalesced save path as streamed agent events, so VM teardown after a successful stdin write does not drop the user's message from durable history
- **Shared local user-message persistence**: `sendReserved()` and `steer()` both flow through one small private VM helper for inserting the user `ConversationEventRecord`, patching the grouped-history cache immediately, and scheduling the coalesced save. Keep this shared owner inside `ConversationViewModel` instead of extracting a separate service/protocol for what is still one VM-local persistence concern; the immediate grouper patch prevents the centered empty-thread shell from reappearing in the gap between a successful stdin write and the later `@Query` merge.
- **Stopped-thread outbound routing**: one private helper owns stale-worktree repair plus the `needsSetup` / respawn / live-send branch, so `queueOrSend()`, queued auto-send, `retryNextQueuedMessage()`, and `answerPrompt()` cannot drift into different recovery behavior
- **Transport vs display text**: staged context is prepended only to the agent-facing transport payload; the persisted user message keeps the original authored text only
- **Error clearing**: starting a new setup/send/steer clears previous `lastTurnError`
- **Transient events**: `.messageChunk` and sub-agent control events must NOT insert SwiftData records; top-level `.messageChunk(parentToolUseId: nil)` appends to `streamingText`, sub-agent chunks do NOT leak into top-level bubble; sub-agent control events update `grouper.items` immediately (live UI, no save needed)
- **Save coalescing**: `scheduleSave()` uses an adaptive delay (~350ms while busy, ~150ms when idle); each save snapshots its own observed-index + generation before sleeping so a trailing task from an older VM cannot advance the shared replay boundary past what that VM's `ModelContext` actually flushed; if newer events arrive while that task is already scheduled/in flight, flip a small follow-up flag so one more coalesced pass runs afterward instead of leaving `lastPersistedEventIndex` stranded behind rows that were already saved; `markPersisted` only on success and only for that captured generation; canceled saves must exit before `modelContext.save()` or `markPersisted`, and save failure preserves `lastPersistedEventIndex` so reconnects replay from last durable boundary without advancing a replacement buffer
- **Save-task identity**: canceled or trailing save tasks must not clear a newer `saveTask` / follow-up-save slot after first-setup rollback rebinding or rapid event bursts schedule a replacement task
- **Queue draining**: queued messages are re-read from `peekNext()` inside the auto-send task, tagged via `inFlightQueuedMessageID`, and removed only after a successful send; failed respawn/send keeps the entry queued at the head for explicit retry or dismiss, later composer sends append behind that stalled head instead of bypassing it, and the user cannot dismiss the already-committed head mid-send
- **Queued completion UX**: a successful `.tokens` with a queued head does not represent a user-visible "done" state yet — the auto-send handoff suppresses plain completion notifications and later UI status derivation treats the thread as effectively busy until the next send succeeds or fails
- **Queued-head ordering guard**: public direct-send paths that do not intentionally queue (`send()`, `answerPrompt()`) must reject while a queued head is stalled so later outbound traffic cannot leapfrog that head
- **Subscription lifecycle**: `subscribe()` replaces `state.activeSubscriptionToken` before starting a new task, and the task re-checks that token before `handleEvent` and EOF cleanup so a canceled older subscription cannot double-persist rows or clear live UI state for the replacement stream; `deinit` cancels both `subscriptionTask` and any pending `saveTask` so ordinary navigation churn does not temporarily retain the VM through a sleeping/coalescing save
- **Reconfigure**: rejects calls while a turn is still active or an outbound send is already reserved (UI disabling is UX, not the correctness boundary), then sets `isReconfiguringSession` for the full fork-session window; clears session-scoped grouper caches (pending tools, summary cache, sub-agents, prompt-suppression IDs) but preserves rendered history; clears `showPermissionBanner` and stale denied-tool names only after successful respawn; if Claude had to fall back to a fresh `--session-id` launch because its resumable artifact was missing, the UI must surface a visible warning that local history is still shown but provider context restarted fresh; awaits any pending coalesced save before resetting replay cursors; re-subscribes and preserves `ConversationState`; queued messages remain queued and require explicit retry after the new session is ready
- **Session continuity notice**: `SessionLaunchDecision.continuity` updates the shared `ConversationState.sessionContinuityNotice` on ordinary spawn, respawn, and reconfigure paths; the warning is independently dismissible from the permission banner and clears again on a later continuity-preserving spawn
- **Context isolation**: all SwiftData writes resolve models inside the VM's injected `ModelContext` before mutation
- **Permission banner gating**: denied `Write` / `Edit` / `MultiEdit` tool names surface the provider's suggested write-escalation CTA, but denied Bash / AskUserQuestion turns remain dismiss-only even though the banner itself still appears
- **ConversationState lifetime**: survives VM deinit (same app session), but NOT app relaunch / archive / `kill()`
- **Launch-scoped pending state**: queued messages, staged context, and draft text are intentionally launch-scoped in v1 and may be lost on app quit/crash even though provider resume can preserve the active committed turn
- **Prompt answer flow**: `answerPrompt()` throws while `turnState.isActive` or `state.isSendingMessage`; updates the persisted tool_call record only after successful send; patches the existing prompt block in place after save instead of refetching the full conversation
- **Turn completion**: auto-send is triggered only by successful `.tokens` (no `isError`, no permission denials), not stream EOF; terminal `.tokens` also clear stale top-level `streamingText` so cancellation/error/permission-denied turns cannot leave a ghost `StreamingBubble`; `turnState` stays busy across that automatic follow-up until the next send either succeeds or fails; `.stop` is idempotent cleanup only; stream `.error` persists `ErrorBanner` but does not populate `lastTurnError`
- **Cancel**: sends SIGINT only; does NOT synchronously call `endTurn()` or clear `streamingText`
- **Auto-send respawn**: respawns agent if dead (up to `maxRespawnAttempts`), uses worktree path, preserves `selectedModel`/`permissionMode`/`effort`; success resets `respawnAttempts`; failure sets `lastTurnError`
- **Staged context**: `queueOrSend()` while busy snapshots current `stagedContext` into the queued entry and clears live banner; auto-sent messages use their captured snapshot; dismissing the last queued entry that owned staged context restores that context back to the live input banner
- **Steering**: `steer()` is the direct mid-turn stdin path for Claude/v1 and must reject calls while `turnState.isActive == false`; no generic fallback for non-steering providers yet
- **Stream ending**: still clears `streamingText` as the last-resort EOF safety net if the provider exits before a terminal `.tokens` or final `.message(assistant)` arrives
- **Setup flow**: `needsSetup` driven by persisted `hasCompletedInitialSetup`; `queueOrSend()` routes to `setupAndStart()` when true; worktree/runtime are rolled back on worktree-metadata save failure, spawn/setup save failure, or first-send transport failure (including restoring `hasCompletedInitialSetup = false` before the rollback save, canceling the failed runtime's local subscription/save tasks, surfacing `destroyRuntime()` cleanup failures instead of swallowing them, clearing path/branch only after confirmed cleanup, then rebinding a fresh `ConversationState` from AgentsManager so draft/model/staged-context retry UI survives the destructive rollback). If worktree cleanup itself fails after the thread was already marked complete, restore `hasCompletedInitialSetup = true`, preserve the surviving worktree metadata, and reuse that worktree on retry instead of allocating a second one; the centered pre-history Retry UI therefore keys off "no persisted/live history yet + `lastTurnError`", not `needsSetup` alone. Skips worktree when `useWorktree` is false; derives slug from first message; sets/clears `setupPhase` on both success and failure
- **Missing worktree repair**: before a stopped worktree-backed thread respawns or retries a queued head, `repairMissingWorktreeIfNeeded()` detects a vanished on-disk worktree, appends the old branch name into `pendingCleanupBranches` (deduped), clears `branch` / `worktreePath`, flips `hasCompletedInitialSetup = false`, saves that demotion, and lets the current send fall back into the normal first-message setup flow instead of surfacing a generic spawn failure
- **Retry draft preservation**: first-message rollback preserves the submitted `message` argument itself, not the already-cleared `inputDraft`, so the centered Retry state always restores the original first prompt after destructive cleanup, including the preserved-worktree path where `needsSetup` remains false
- **Respawn/spawn**: `needsRespawn()` driven by `isRunning()` not sidebar status; the shared stopped-thread outbound helper respawns when dead and falls back to setup when repair demotes the thread; `makeSpawnConfig()` is single owner for all spawn-time fields, including queued auto-respawn after `.tokens`; public `startAgent()` acquires `withOutboundReservation()` before calling the internal `startAgentReserved()` helper so direct starts cannot race later sends; `prepareForSpawn()` is reused by that reserved path and by `reconfigureSession()`; auto-trust only for worktree-backed threads

### Replay Boundary Example

Use this walkthrough when implementing the save/replay path around `EventBuffer`, `ConversationState`, and VM replacement:

1. Generation `A` is active. The VM consumes event index `41`, increments `lastObservedEventIndex` to `41`, and `scheduleSave()` snapshots `(generation: A, observedIndex: 41)`.
2. Before that save wakes up, the user navigates away and back. The old subscription is canceled, a new VM subscribes, and `state.activeSubscriptionToken` changes so the stale task cannot keep handling events or run EOF cleanup.
3. If the runtime was also replaced in the meantime, the new subscription now points at generation `B` and starts replay from `lastPersistedEventIndex`, not `41`, because `41` was only observed, not durably saved yet.
4. When the old save task finally wakes up, it only calls `markPersisted` if `state.activeBufferGeneration` still matches `A`. If the generation changed to `B`, the stale task exits without advancing replay state for the replacement buffer.
5. The new VM therefore replays anything between the last durable boundary and the new stream exactly once, instead of skipping unsaved rows or letting stale tasks clear the replacement UI state.

## SetupPhase

Standalone enum for thread setup progress, used by `ConversationState.setupPhase`. Defined separately from `ConversationViewModel` so it's available at Phase 3 step #9 (`ConversationState`) without depending on step #13 (`ConversationViewModel`).

```swift
enum SetupPhase {  // Skep/Utilities/SetupPhase.swift
    case creatingWorktree   // Worktree creation, including any setup script inside WorktreeManager
    case startingAgent      // Agent process spawning
}
```

---

Agent lifecycle/status details live in [Part 2g](part2g-status-and-lifecycle.md), permission-mode behavior and reconfigure flow in [Part 2h](part2h-permissions.md), and session storage/resume semantics in [Part 2i](part2i-session.md).

---

## Auto-Naming from First Message

The first user message in a thread can be used to auto-name the thread. The logic lives in a pure function for testability:

```swift
/// Derives a thread name from the user's first message, or returns nil if the message
/// is not suitable for naming (too short, a confirmation, or a slash command).
/// Truncates to ~50 characters at a word boundary if needed.
static func threadName(from message: String) -> String? {  // Skep/Utilities/AutoNaming.swift
    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 10 else { return nil }
    let lower = trimmed.lowercased()
    let confirmations: Set<String> = ["y", "yes", "ok", "sure", "yep", "yeah", "yea", "go", "do it", "go ahead"]
    if confirmations.contains(lower) { return nil }
    if trimmed.hasPrefix("/") { return nil }
    if trimmed.count <= 50 { return trimmed }
    // Truncate at the last word boundary before 50 characters
    let prefix = trimmed.prefix(50)
    if let lastSpace = prefix.lastIndex(of: " ") {
        return String(prefix[prefix.startIndex..<lastSpace]) + "..."
    }
    return String(prefix) + "..."
}
```

Called by the VM-local `insertLocalUserMessage(...)` path used by `sendReserved()` and `steer()`. That keeps first-message auto-naming on the real setup path (`queueOrSend()` → `setupAndStart()` → `sendReserved()`), not just on later ordinary sends.

**Unit tests for `threadName(from:)`:** cover length bounds, truncation, and nil-returning cases. Non-obvious:
- Does not treat `"yes please fix the auth bug"` as a confirmation (>= 10 chars, contains "yes" but isn't only "yes")
- Truncates at word boundary before 50 characters; falls back to hard truncation at 50 if no boundary exists

`ConversationViewModel.answerPrompt()` uses two pure helpers — one for the agent-facing follow-up text and one for the compact persisted summary shown on answered prompt blocks. The compact summary uses the question text (trimmed), not the optional chip/header label from the prompt UI:

```swift
static func formatPromptAnswers(answers: [(question: String, answer: String)]) -> String {
    answers.map { question, answer in
        "For the question '\(question)': \(answer)"
    }.joined(separator: "\n")
}

static func promptSummary(answers: [(question: String, answer: String)]) -> String {
    answers.map { question, answer in
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(trimmedQuestion): \(answer)"
    }.joined(separator: "\n")
}
```

### Prompt Answer Persistence Example

`answerPrompt()` does **not** append a new event row for the read-only answered state shown on a restored prompt block. Instead, after the answer has been sent successfully, it mutates the existing `AskUserQuestion` `tool_call` record in place and stores the compact summary in that row's `content`.

Example:

| Persisted row | Before answer | After answer |
|---|---|---|
| `tool_call` (`toolId = prompt-123`, `toolName = AskUserQuestion`) | `content = nil` | `content = "Language: Swift\nFramework: SwiftUI"` |
| Event count | 25 rows | Still 25 rows |

Because the persisted row count does not change, the incremental `ChatItemGrouper` cache cannot rely on `events.count` to notice that the prompt block should become read-only. Instead of refetching the full persisted snapshot, `answerPrompt()` calls `state.grouper.markPromptAnswered(promptId:summary:)` after the save succeeds so only the affected prompt block is updated.

---

## Context Injection

Text can be staged to be prepended to the user's next message. `ConversationState` (owned by `AgentsManager`) holds a `stagedContext: String?` property. UI actions (e.g. right-clicking a file in the diff viewer and selecting "Ask about this file") set this property. When the user sends immediately, `ConversationViewModel.send()` prepends the staged context to the agent-facing transport payload, then clears it; the persisted/rendered user bubble still shows only the text the user authored, not the hidden injected file excerpt. When the user queues while the agent is busy, `queueOrSend()` snapshots the current `stagedContext` into that queued entry and clears the live banner immediately; later banner dismissals or replacements do not retarget the already-queued message. If the user dismisses the queued message that currently owns staged context and no other queued entry still owns one, that snapshot is restored back to `state.stagedContext` so the context is not silently lost. Because `ConversationState` survives VM destruction, any still-live staged context persists when the user navigates away and back.

When staged context exists, the chat input shows a dismissible banner above the text field:

```
┌─────────────────────────────────────────────────────┐
│  📎 Including: src/auth.swift:45-80            ✕    │ ← staged context banner
├─────────────────────────────────────────────────────┤
│  What's wrong with this function?                   │
├─────────────────────────────────────────────────────┤
│   🔷 Opus ▾   ⚡ High ▾   🔒 Default ▾      ⬆    │
└─────────────────────────────────────────────────────┘
```

The banner shows a 📎 icon, a truncated description of the context, and a ✕ dismiss button. Dismissing clears `stagedContext` without sending. The full context text (which may be long — e.g. a file excerpt) is prepended to the user's message on send, not shown in the banner. If the user queues a message while busy, that queued entry owns the current staged-context snapshot and the input banner clears immediately because the "next message" has already been claimed.

---

## Message Queuing and Steering

Messages can be queued while the agent is busy and sent automatically when the turn completes. The user can also "steer" the agent mid-turn to redirect its work. The `MessageQueue` type (defined in Part 2a) holds pending messages plus any staged-context snapshot captured when each message was queued. `ConversationViewModel.queueOrSend()` routes to either `send()` (if idle) or `messageQueue.enqueue(message, stagedContext: ...)` (if busy). The brief pre-turn reservation window (`state.isSendingMessage`) also counts as busy for routing, so a second send cannot slip past a respawn/setup/stdin-write already in progress. On successful turn completion, the VM attempts the queued head with that captured context snapshot instead of whatever live `stagedContext` happens to exist later, and only removes the entry after the send succeeds. If the user manually removes a queued entry that was the only owner of staged context, the VM restores that snapshot back to the live input banner so queue dismissal behaves like "give me this context back" rather than "discard it forever."

### Send-Path Routing Matrix

| Situation | Entry point | Result |
|---|---|---|
| Brand-new thread (`needsSetup == true`) | `queueOrSend()` → `setupAndStart()` | Create worktree if needed, run initial spawn path, then send the first message |
| Idle thread with a live process | `queueOrSend()` → `send()` | Prepend any live `stagedContext` to the agent-facing payload, persist only the user-authored message text, and call `beginTurn()` |
| Idle thread with no live process | `queueOrSend()` → shared stopped-thread outbound helper | Re-spawn from persisted thread/session state, then send the message |
| Send already reserved (`state.isSendingMessage == true`) | `queueOrSend()` → `messageQueue.enqueue()` | Treat the in-flight setup/respawn/stdin-write window like busy time so a second outbound action queues instead of racing the first |
| Busy thread, normal follow-up message | `queueOrSend()` → `messageQueue.enqueue()` | Capture the current `stagedContext` into the queued entry and clear the live banner immediately |
| Busy thread, user wants to redirect current work | `steer()` | Send a mid-turn stdin message immediately and persist the steering message without queueing |
| Prompt answer submitted while a turn is still active or outbound send is already reserved | `answerPrompt()` | Throw an error instead of queueing so the prompt UI is not marked answered before the current turn actually finishes or while another outbound path is mid-flight |

This matrix is the intended implementation checklist for the chat composer: every outbound path goes through one of the rows above, and only the busy non-steering path is allowed to queue.

---

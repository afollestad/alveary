## Agent Runtime

These instructions cover provider-neutral runtime management under `Alveary/Services/Agent/Runtime/` — lifecycle, spawning, event buffers, conversation state, and desktop-notification gating. Tool approval is nested and owns its own rules: `Alveary/Services/Agent/Runtime/ToolApproval/AGENTS.md`.

> **READ FIRST — approval state lives in this scope, but its rules do not.** `EventBuffer` carries `pendingLiveToolApprovals`, `resolvedLiveToolApprovals`, and `hasDeferredToolStop`, seeded in `DefaultAgentsManager+AgentCLIKitBuffers.swift`, flagged in `+StreamEvents.swift`, and read in `+AgentCLIKitStatus.swift`. Read the nested file named above before touching any of them.

**Keep a rule here only when the code that would violate it is not the code that documents it.** Mechanism whose only reader is its own file belongs in a doc comment: `requiresProviderRestart`'s reason for existing on the protocol, the `.agentStatusChanged` bus contract, why a handoff archives the session it drops, and why a whitespace-only chunk with no live thought is padding each carry theirs.

- `AgentsManager.destroyRuntime()` is the single public owner for waiting on destructive teardown. A UI flow may call `kill(conversationId:)` first when it needs the visible row gone immediately, but it must still call `destroyRuntime(conversationId:)` as the wait and cleanup phase rather than reimplementing wait loops or direct session-map removal.
- `AgentsManager.suspendRuntime()` is non-destructive terminal cleanup. Suspend only idle, non-waiting runtimes with no live background tasks (`AgentRuntimeStatus.liveBackgroundTaskCount`, mirrored into `ConversationState` from status like goals), preserving the provider session, Alveary binding, conversation state, and reusable approvals so the next manual turn resumes. Call `isRuntimeSuspended(conversationId:)` before releasing terminal lifecycle ownership, because provider status can briefly lag the transcript boundary.
- `ConversationRuntimeStore` is the canonical composer-state owner across view and app-root actions, and it owns the run-wide in-memory fence that blocks every conversation in a scheduled Task until terminal persistence and runtime suspension finish.
    - **Initial-setup rollback must use `destroyRuntimePreservingState`** so root-routed work cannot fork into a fresh state during teardown. Bind retained state after ordinary failure; cancellation replaces it and transfers active view-mount registration before binding the replacement.
- **A whitespace-only chunk is a reasoning section break, never thought content.** AgentCLIKit emits one between Codex reasoning sections and at Claude thinking-block starts, so `ConversationState.appendThoughtChunk` must not let one start a section, bump `thoughtSequence`, or clear `completedThoughtText`.
- **Agent environments take `PATH` from `ExecutableSearchPath.augmentedPath`, never `ProcessInfo` verbatim.**
- **`DefaultAgentsManager` is `AgentCLIKit`-only.** Provider launch, provider process lifetime, stream decoding, hook transport, provider approval policy, transcript-path logic, and restored transcript inspection all stay in `AgentCLIKit`.
    - `DefaultAgentsManager+Spawn.swift` stays host orchestration: event buffer and status work belong in the `AgentCLIKit` companions, and stream-status mapping in `DefaultAgentsManager+StreamEvents.swift`.
- **Treat reconfiguration's `.nextTurnRequired` as a staged-settings outcome** for the next outbound turn, not a fatal provider failure or a reason to roll back the user's persisted picker state.
- **Runtime speed mode stays per-session.** Pass `AgentSpawnConfig.speedMode` through the AgentCLIKit bridge; never launch shared provider runtimes with global fast flags or app-wide speed enablement.
- **Every Alveary-launched Claude process disables native scheduling** with `CLAUDE_CODE_DISABLE_CRON=1` and a merged `RemoteTrigger` denial. Merge into existing configured deny-tool values instead of appending a competing variadic option.
- **Preserve canonical workspace-root strings verbatim in the host-tool fallback retry.** A canceled or older replay generation must never disable the replacement runtime. `Alveary/Services/HostMCP/AGENTS.md` owns the retry itself.
- **Session handoff replaces the provider session binding through `startFreshSession(...)`.** It must remove old session approvals, drop the old event buffer, and spawn with `forkSession: false`; do not route it through normal settings reconfiguration.
- **A settled `.error` outranks polled status, so host-initiated new work must clear it.** `idleAgentCLIKitActivitySignal` owns why. A turn started through `runtime.*` plus `refreshAgentCLIKitStatus`, rather than `sendMessage` or a buffer install, otherwise leaves the row red while it runs.

### Notification Gating

- Runtime notification gating is terminal-aware:
    - **Suppress hidden activity.** Hidden runtime turns, including one-shot commit-message generation, must not raise desktop notifications. Classify terminal events from the turn visibility captured *before* terminal cleanup resets the buffer state.
    - **The status stream is a terminal boundary too.** `handleRuntimeTurnActiveStatus` must stash the turn visibility like the event path does; the two streams race, and a hidden-only flip silently drops the completion notification.
    - **Suppress progress token notifications.** `usage_update` token rows are interim usage, not turn completion.
    - **Treat `tool_deferred` as waiting.** A successful `tool_deferred` token stop means the runtime is waiting on an approval or prompt; notify from the `tool_approval` request instead of announcing that the agent finished.
    - **Suppress resolved denials.** After the user denies a tool approval, later provider token rows reporting that same `permission_denial` are confirmation, not a new request.
    - **Coalesce pending-action prompts.** Parallel live hooks produce several approval rows for one decision surface, so send one pending-action notification per batch and reset it after resolution or failure, terminal completion, error, stop, or a new runtime generation.
- **Context compaction lifecycle events are transcript-only** and never notify. When one arrives during root assistant streaming, clear the transient streaming text before rendering the centered note.

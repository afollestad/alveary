## View Models

These instructions apply to files under `Alveary/ViewModels/`.

### Ownership Boundary

- Keep view models as coordination layers: route UI intent, own observers/watchers, and delegate service-backed state to focused collaborators when state becomes shared or long-running.
- `ConversationControllerRegistry` is the app-scoped owner for conversation view models. View and background leases for one conversation must share its subscription, queue drain, persistence path, and terminal outcome stream.
- Keep background retention distinct from view mounting. Background leases may keep provider work alive, but only view leases may change `ConversationState.isViewMounted`.
- Terminal outcomes come from explicit `ConversationState` boundary snapshots, not sampled idle UI state. Keep `tool_deferred` boundaries open through delayed approvals, and publish terminal results only after the required record flush; preserve resumable sessions and retain the controller when maintenance fails.
- Scheduled-run background leases defer automatic suspension until their executor persists the run and unread state, then explicitly flushes and suspends the runtime. Verify the provider process is actually gone and retry transient status lag before releasing the controller lease or coordinator-owned keep-awake assertion.
- Scheduled management observes persisted scheduler change notifications. Keep Run-now actions pending until the coordinator reports claim resolution; elapsed-time delays are not a synchronization boundary.
- A linked nonterminal scheduled run or in-memory scheduled finalization blocks ordinary outbound, hidden commit generation, session handoff, and settings/reconfiguration producers. Transcript Stop must route through coordinator-owned user-stop handling so the run is interrupted and coalesced pending work is cleared before provider cancellation.
- A nonterminal provider goal remains controller-owned work even while its runtime is idle or paused. Keep its controller and resumable runtime until the goal reaches a terminal state.
- **Own side effects.** View models own mutable runtime state, persistence, and side effects.
- **Keep presentation derived.** Renderer-neutral `*Presentation` types may derive display/action values from view-model state, but must not replace view-model ownership or perform service/model mutations.
- Contextual editor view models cache drafts by stable target and give each session a generation UUID. Closing discards only the active target; deactivation for another root pane preserves it; async completions may update only the same live generation.

### File Organization

- Put feature-specific view-model rules in the narrowest subfolder guidance, such as `Alveary/ViewModels/DiffViewer/AGENTS.md`.
- Keep `ConversationViewModel` companions focused by behavior:
  - **Route outbound work.** Put message sending, queued-message dispatch, and transport message construction in `ConversationViewModel+MessageDispatch.swift`.
  - **Recover stale provider sessions locally.** If a stopped provider session cannot be resumed, start a fresh provider session for the same conversation and attach `Conversation.restoreContextFromHistory()` through staged transport context. Normal sends, queued sends, retries, and session handoff should not fail only because provider-native history disappeared.
  - **Handle inbound events.** Put provider event filtering, token stop handling, and synthetic event records in `ConversationViewModel+EventHandling.swift`.
  - **Record local user messages.** Put transcript-local user message insertion and secondary-conversation preview title side effects in `ConversationViewModel+LocalMessages.swift`; main thread titles come from provider metadata in `ConversationViewModel+EventHandling.swift`.
  - **Persist runtime state.** Put debounced SwiftData saves and runtime-buffer cursor acknowledgement in `ConversationViewModel+Persistence.swift`.
  - **Stage session settings.** Keep pending next-turn model, effort, speed, permission, and plan-mode changes runtime-scoped on `ConversationState`; stored thread fields can reflect the selected UI value immediately, but continuations must use the live session config until a new visible turn consumes the staged change.
  - **Keep speed provider-scoped.** Route speed-mode UI through `applySpeedModeChange(_:supportsSpeedMode:)`; Fast is Codex-only until provider status reports support, and stale unsupported Fast must normalize to Standard before new sends.
  - **Keep plan separate.** Route plan-mode UI through `applyPlanModeChange(_:)`; do not encode plan as a permission dropdown value. Use runtime collaboration-mode events/status to sync `runtimePlanModeEnabled`, including clearing it after successful `ExitPlanMode`.
  - **Separate visible and transport text.** `QueuedMessage.transportText` and send-attempt transport overrides are provider-facing only; persisted user rows, drafts, queued chips, worktree slugs, slash commands, and titles must use visible text.
  - **Drain resume cursors.** Fallback approval resumes must wait for all queued debounced saves, including follow-up saves, before resetting subscription tracking.
  - **Bound stream coalescing.** Live root-assistant chunk batching should use count/size thresholds plus a short max-latency flush so small provider deltas cannot sit buffered indefinitely, while preserving provider event order.
- Keep automatic session handoff terminal-aware:
  - **Mark pending from usage.** Context-window token rows may mark handoff pending before the provider turn is complete.
  - **Trigger on completion.** Start handoff only from a successful terminal token stop, keep queued messages behind pending handoff, and clear pending state on errors, interruptions, explicit stops, or handoff start.
- Keep live tool-approval decisions terminal-aware:
  - **Allow stays active.** Live approval can continue the provider turn, so leave `turnState` active until a terminal event arrives.
  - **Deny ends UI turn.** After a live denial decision is accepted, end the local turn even if Claude's trailing permission-denial token is delayed; later terminal tokens are still safe to process.
  - **Clear plan exits early.** A live `ExitPlanMode` approval should stop blocking the composer once the stream reports a non-plan permission mode or a successful matching tool result; do not wait for the final token while implementation is already streaming.
  - **Stage denied plan follow-ups.** A denied or dismissed `ExitPlanMode` approval is terminal for the confirmation UI; clear the pending approval and end the local turn immediately.
    If the denial includes custom follow-up text, keep it hidden and busy until the denied turn reaches a captured terminal boundary or the silent-turn fallback fires, then send it ahead of older queued messages.
    Plain Claude revision guidance is transient `ConversationState`, not SwiftData; consume it only for eligible normal feedback sends, keep revision-marked queued messages plan-gated and non-steerable, re-arm on queued edit or cancellation rollback, and clear on queued dismissal, provider/session mismatch, plan-mode exit, session handoff, fresh `ExitPlanMode`, or failed approval resolution.
  - **Mirror live plan mode.** Runtime `permissionModeChanged` state is the source of truth for live permission decisions while a session is live; while next-turn settings are pending, fall back to the pre-change permission snapshot instead of the staged stored thread mode.
  - **Answer the newest prompt approval.** `AskUserQuestion` answers must resolve the newest unresolved same-prompt approval record before using stale in-memory approval state or falling back to normal Q/A sends.
  - **Dismiss prompts as interruptions.** `AskUserQuestion` dismissal should resolve the provider prompt as denied/cancelled, mark the prompt handled without a submitted-response card, end the active turn, and allow the `Interrupted` transcript note. Suppress only in-flight fallback events while the dismissal call is still resolving; do not keep durable prompt-dismiss state that can swallow later sends.
  - **Preserve fallback batches.** Fallback `tool_deferred` ends the local turn before delayed sibling approvals can arrive.
    Same-session same-family pending approvals should stay unresolved for batch resolution instead of being superseded only because `turnState.isActive` is false.
    Interleaved read-only tool results should not break same-family approval discovery; exclude approval rows only when their own tool result has arrived.
  - **Keep unrelated approvals actionable.** A new approval should not blanket-supersede older unresolved approvals; resolving one approval should rehydrate the next unresolved approval so the composer stays blocked until all actionable approvals are handled.
  - **Do not reopen completed approvals.** A matching tool result terminalizes unresolved approval rows, and late approval events for that tool ID must not recreate pending approval UI.
- Thread removal must route through `SidebarViewModel` lifecycle methods so runtime teardown, notification cleanup, provider-native Codex archive, worktree cleanup, and branch cleanup stay coordinated. Views that need to delete a thread, including project-trust denial flows, should receive a focused delete closure instead of calling `ModelContext.delete(_:)` on `AgentThread` directly.
- A Task row with pending scheduled-worktree cleanup is the user-visible retry owner. Complete that pending cleanup before committing permanent thread deletion; do not leave retry-only provenance on a threadless run.
  Reject overlapping cleanup attempts for the same run while its durable branch-retirement fence may represent an in-flight deletion. Once branch ownership is durably retired, a later retry may clear that provenance only after identity-aware removal proves the persisted worktree and ownership sidecar are absent; leave the unprovable branch behind.
- Archiving or permanently deleting a Task linked to a scheduled run must quiesce that coordinator launch before the SwiftData commit. Stop nonterminal runs, but only wait for already-terminal runs so runtime finalization and notification routing finish without mutating historical schedule state.
- `ArchivedTasksSettingsViewModel` owns archived Task fetching and Settings-side lifecycle state. Permanent deletion must preserve the row and app selection state on pre-commit failure; after a post-commit cleanup failure, remove stale selection, bookmark, conversation, and launch-restore references while surfacing the cleanup diagnostic.
- Keep draft deletion atomic with its lifecycle boundary:
  - Commit the SwiftData removal before the first `await` so concurrent New Thread requests cannot reuse or materialize the deleted row.
  - Remove conversation attachment directories only after runtime teardown has been attempted, including teardown-failure paths.
  - Before a targeted mutation that may call `ModelContext.rollback()`, synchronously save pre-existing shared-context changes.
    A target failure must not discard unrelated pending work.
- Project and Task drafts are independent mode-keyed identities. Materializing or deleting one mode must not clear the other mode's cached draft, creation task, or pending Project destination.
- Pinned sidebar ordering is mode-explicit: Task threads use the Task drag domain and stay independently pinned even when backed by a pinned Project; Project pin normalization may absorb only Project-mode child threads.
- Task folder grants may change only while the conversation is fully idle. Phase 3 also limits editing to Tasks with exactly one live conversation; lift that only with thread-wide runtime coordination. Persist canonical roots, restart an already-tracked idle runtime, leave suspended runtimes asleep, and roll back both persistence and runtime configuration when replacement cannot be applied.

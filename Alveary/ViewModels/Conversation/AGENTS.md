## Conversation View Models

These instructions apply to files under `Alveary/ViewModels/Conversation/`.

### Controller Ownership

- `ConversationControllerRegistry` is the app-scoped owner for conversation view models. View and background leases for one conversation share its subscription, queue drain, persistence path, and terminal outcome stream.
- Keep background retention distinct from view mounting: background leases may keep provider work alive, but only view leases change `ConversationState.isViewMounted`.
- Terminal outcomes come from explicit `ConversationState` boundary snapshots, not sampled idle UI state. Keep `tool_deferred` boundaries open through delayed approvals, publish terminal results only after the required record flush, and preserve resumable sessions plus the controller when maintenance fails.
- A nonterminal provider goal remains controller-owned work even while its runtime is idle or paused; keep its controller and resumable runtime until the goal reaches a terminal state.
- Scheduled-run background leases defer automatic suspension until their executor persists the run and unread state, then explicitly flush and suspend the runtime. Verify the provider process is actually gone and retry transient status lag before releasing the controller lease or coordinator-owned keep-awake assertion.
- A linked nonterminal scheduled run or in-memory scheduled finalization blocks ordinary outbound, hidden commit generation, session handoff, and settings/reconfiguration producers. Transcript Stop routes through coordinator-owned user-stop handling so the run is interrupted and coalesced pending work cleared before provider cancellation.
- **`ThreadStatus.waitingForUser` unions runtime waiting with pending decisions.** The runtime only reports waiting while a provider process is blocked; a proposal card or link question completes its turn normally, so `ConversationDecisionAttention` supplies the rest and `displayStatus` treats both alike. A new awaiting-user transcript surface enrolls by adding a source there, never by adding a second input to `ThreadStatus`.
    - **Never seed the durable half into `DefaultAgentsManager.statusSnapshot`.** That snapshot also drives the keep-awake assertion and the sudden-termination gate, so a prompt recovered from history would hold a power assertion open for a turn nobody is running.
    - **`UnresolvedApprovalRegistry` and `SidebarViewModel.hasUnresolvedApproval` are not duplicates.** The registry counts only never-answered rows, because live ones are already blue from the runtime; the fork/Task-move gate additionally counts the transient `.pending`/`.approving` statuses. Both read `ModelContext.hasToolApprovalResolution`, which owns what "still open" means.

### Companion Files

Keep `ConversationViewModel` companions focused by behavior:

- **Route outbound work** — message sending, queued dispatch, transport message construction — through `ConversationViewModel+MessageDispatch.swift`.
- **Recover stale provider sessions locally.** If a stopped provider session cannot resume, start a fresh one for the same conversation and attach `Conversation.restoreContextFromHistory()` through staged transport context; sends, retries, and handoff must not fail only because provider-native history disappeared.
- **Handle inbound events** — provider event filtering, token stop handling, synthetic records — in `ConversationViewModel+EventHandling.swift`.
- **Record local user messages** in `ConversationViewModel+LocalMessages.swift` (plus secondary-conversation preview titles); main thread titles come from provider metadata in `+EventHandling.swift`.
- **Persist runtime state** — debounced SwiftData saves and runtime-buffer cursor acknowledgement — in `ConversationViewModel+Persistence.swift`.
- **Stage session settings.** Pending next-turn model, effort, speed, permission, and plan-mode changes stay runtime-scoped on `ConversationState`; stored thread fields may reflect the selected UI value immediately, but continuations use the live session config until a new visible turn consumes the staged change.
- **Keep speed provider-scoped.** Route speed-mode UI through `applySpeedModeChange(_:supportsSpeedMode:)`; Fast is Codex-only until provider status reports support, and stale unsupported Fast normalizes to Standard before new sends.
- **Keep plan separate.** Route plan-mode UI through `applyPlanModeChange(_:)`; never encode plan as a permission dropdown value. Sync `runtimePlanModeEnabled` from runtime collaboration-mode events/status, including clearing it after successful `ExitPlanMode`.
- **Separate visible and transport text.** `QueuedMessage.transportText` and send-attempt transport overrides are provider-facing only; persisted user rows, drafts, queued chips, worktree slugs, slash commands, and titles use visible text.
- **Drain resume cursors.** Fallback approval resumes wait for all queued debounced saves, including follow-ups, before resetting subscription tracking.
- **Bound stream coalescing.** Live root-assistant chunk batching uses count/size thresholds plus a short max-latency flush so small deltas cannot sit buffered indefinitely, preserving provider event order.

### Handoff And Approvals

- Keep automatic session handoff terminal-aware: context-window token rows may mark handoff pending before the turn completes, but handoff starts only from a successful terminal token stop; queued messages stay behind pending handoff, and pending state clears on errors, interruptions, explicit stops, or handoff start.
- Keep live tool-approval decisions terminal-aware:
  - **Allow stays active.** Live approval can continue the provider turn; leave `turnState` active until a terminal event.
  - **Deny ends UI turn.** After a live denial is accepted, end the local turn even if Claude's trailing permission-denial token is delayed; later terminal tokens remain safe to process.
  - **Clear plan exits early.** A live `ExitPlanMode` approval stops blocking the composer once the stream reports a non-plan permission mode or a successful matching tool result; do not wait for the final token while implementation is already streaming.
  - **Let an approved plan exit consume staged model and effort** — the single exception to "continuations keep the live config": implementation is new work, and the plan overlay offers a reasoning dropdown precisely so the user can implement on a different model.
    - **Only model and effort.** Build the restart config from `makeSpawnConfig(settingsSource: .currentContinuation)` and override the two through `AgentSpawnConfig.withModel(_:effort:)`; `.nextTurn` would also swap permission mode, speed mode, and host-tool exposure (defaulting `hostToolExposure` to `.ordinaryOutbound`).
    - **Restart, because Claude cannot change model in place.** `ClaudeProviderAdapter.reconfigure` returns `.restartRequired` (`--model`/`--effort` are launch flags). `approveExitPlanMode` sets `requiresProviderRestart` so resolution takes the deferred respawn path, and `resumeDeferredToolUse` must then treat the approval as *not* live so spawn preparation and subscription reset still run.
    - **Hold `isReconfiguringSession` across it** — teardown plus respawn takes seconds, and without it `ChatPresentation` falls to `.busy(canStop: true)` and offers Stop mid-restart.
    - **Keep plan mode on for the respawn.** `spawnPlanModeOverride` forces it while an `ExitPlanMode` approval is pending, or the replayed tool is rejected with `You are not in plan mode.`
    - **Denial does not restart.** Deny and dismiss leave the change staged; the follow-up is a new visible turn and consumes it there.
  - **Stage denied plan follow-ups.** A denied/dismissed `ExitPlanMode` approval is terminal for the confirmation UI: clear the pending approval and end the local turn immediately.
    Custom follow-up text stays hidden and busy until the denied turn reaches a captured terminal boundary or the silent-turn fallback fires, then sends ahead of older queued messages.
    A fallback deferred denial resets subscription tracking mid-resolution, so rebind the staged follow-up's subscription token and event cursor after the resubscribe, and keep the awaiting phase covered by `schedulePendingExitPlanModeFollowUpWatchdogIfNeeded` so an identity guard that can never match again force-drains instead of pinning the composer busy forever.
    Plain Claude revision guidance is transient `ConversationState`, not SwiftData: consume it only for eligible normal feedback sends, keep revision-marked queued messages plan-gated and non-steerable, re-arm on queued edit or cancellation rollback, and clear on queued dismissal, provider/session mismatch, plan-mode exit, session handoff, fresh `ExitPlanMode`, or failed approval resolution.
  - **Mirror live plan mode.** Runtime `permissionModeChanged` state is the source of truth for live permission decisions; while next-turn settings are pending, fall back to the pre-change permission snapshot, not the staged stored thread mode.
  - **Answer the newest prompt approval.** `AskUserQuestion` answers resolve the newest unresolved same-prompt approval record before using stale in-memory state or falling back to normal Q/A sends.
  - **Dismiss prompts as interruptions.** `AskUserQuestion` dismissal resolves the provider prompt as denied/cancelled, marks it handled without a submitted-response card, ends the active turn, and allows the `Interrupted` note. Suppress only in-flight fallback events while the dismissal resolves; keep no durable prompt-dismiss state that could swallow later sends.
  - **Preserve fallback batches.** Fallback `tool_deferred` ends the local turn before delayed sibling approvals arrive; same-session same-family pending approvals stay unresolved for batch resolution instead of being superseded just because `turnState.isActive` is false. Interleaved read-only tool results do not break same-family discovery; exclude an approval only when its own tool result has arrived.
  - **Keep unrelated approvals actionable.** A new approval must not blanket-supersede older unresolved ones; resolving one rehydrates the next unresolved approval so the composer stays blocked until all actionable approvals are handled.
  - **Do not reopen completed approvals.** A matching tool result terminalizes unresolved approval rows; late approval events for that tool ID must not recreate pending approval UI.

### Pull Request Detection

Transcript detection lives in `ConversationViewModel+PullRequestDetection.swift`, hooked into the two message insert sites (`persistEventRecord`, `insertLocalUserMessage`) plus a rescan after draft materialization, which the draft gate skipped. `Alveary/ViewModels/PullRequests/Links/AGENTS.md` owns the link store this feeds.

- **Detect at insert time only.** Fork-copied and rebuilt history never reaches those sites, which is what keeps old transcripts from prompting; the watermark (see `Alveary/Data/AGENTS.md`) fences replays.
- **Never write links here.** Both the automatic and accepted paths post `.pullRequestLinkRequested` for `ContentView` to route into `PullRequestLinksViewModel`; decline and Never are local writes.
- **Filter prompts at render time, do not delete them.** `pendingPullRequestLinkPromptsByMessageID()` drops already-linked and globally suppressed prompts, so a stale entry cannot resurrect a question, and `Never` stays reversible by turning auto-linking on.

## View Models

These instructions apply to files under `Alveary/ViewModels/`.

### Ownership Boundary

- Keep view models as coordination layers: route UI intent, own observers/watchers, and delegate service-backed state to focused collaborators when state becomes shared or long-running.
- **Own side effects.** View models own mutable runtime state, persistence, and side effects.
- **Keep presentation derived.** Renderer-neutral `*Presentation` types may derive display/action values from view-model state, but must not replace view-model ownership or perform service/model mutations.

### File Organization

- Put feature-specific view-model rules in the narrowest subfolder guidance, such as `Alveary/ViewModels/DiffViewer/AGENTS.md`.
- Keep `ConversationViewModel` companions focused by behavior:
  - **Route outbound work.** Put message sending, queued-message dispatch, and transport message construction in `ConversationViewModel+MessageDispatch.swift`.
  - **Handle inbound events.** Put provider event filtering, token stop handling, and synthetic event records in `ConversationViewModel+EventHandling.swift`.
  - **Record local user messages.** Put transcript-local user message insertion and secondary-conversation preview title side effects in `ConversationViewModel+LocalMessages.swift`; main thread titles come from provider metadata in `ConversationViewModel+EventHandling.swift`.
  - **Persist runtime state.** Put debounced SwiftData saves and runtime-buffer cursor acknowledgement in `ConversationViewModel+Persistence.swift`.
  - **Stage session settings.** Keep pending next-turn model, effort, speed, permission, and plan-mode changes runtime-scoped on `ConversationState`; stored thread fields can reflect the selected UI value immediately, but continuations must use the live session config until a new visible turn consumes the staged change.
  - **Keep speed provider-scoped.** Route speed-mode UI through `applySpeedModeChange(_:supportsSpeedMode:)`; Fast is Codex-only until provider status reports support, and stale unsupported Fast must normalize to Standard before new sends.
  - **Keep plan separate.** Route plan-mode UI through `applyPlanModeChange(_:)`; do not encode plan as a permission dropdown value. Use runtime collaboration-mode events/status to sync `runtimePlanModeEnabled`, including clearing it after successful `ExitPlanMode`.
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
  - **Mirror live plan mode.** Runtime `permissionModeChanged` state is the source of truth for live permission decisions while a session is live; while next-turn settings are pending, fall back to the pre-change permission snapshot instead of the staged stored thread mode.
  - **Answer the newest prompt approval.** `AskUserQuestion` answers must resolve the newest unresolved same-prompt approval record before using stale in-memory approval state or falling back to normal Q/A sends.
  - **Dismiss prompts as interruptions.** `AskUserQuestion` dismissal should resolve the provider prompt as denied/cancelled, mark the prompt handled without a submitted-response card, end the active turn, and allow the centered `Interrupted` cue. Suppress only in-flight fallback events while the dismissal call is still resolving; do not keep durable prompt-dismiss state that can swallow later sends.
  - **Preserve fallback batches.** Fallback `tool_deferred` ends the local turn before delayed sibling approvals can arrive.
    Same-session same-family pending approvals should stay unresolved for batch resolution instead of being superseded only because `turnState.isActive` is false.
    Interleaved read-only tool results should not break same-family approval discovery; exclude approval rows only when their own tool result has arrived.
  - **Keep unrelated approvals actionable.** A new approval should not blanket-supersede older unresolved approvals; resolving one approval should rehydrate the next unresolved approval so the composer stays blocked until all actionable approvals are handled.
  - **Do not reopen completed approvals.** A matching tool result terminalizes unresolved approval rows, and late approval events for that tool ID must not recreate pending approval UI.
- Thread removal must route through `SidebarViewModel` lifecycle methods so runtime teardown, notification cleanup, provider-native Codex archive, worktree cleanup, and branch cleanup stay coordinated. Views that need to delete a thread, including project-trust denial flows, should receive a focused delete closure instead of calling `ModelContext.delete(_:)` on `AgentThread` directly.

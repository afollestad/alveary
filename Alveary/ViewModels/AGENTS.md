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
  - **Record local user messages.** Put transcript-local user message insertion and auto-naming side effects in `ConversationViewModel+LocalMessages.swift`.
  - **Persist runtime state.** Put debounced SwiftData saves and runtime-buffer cursor acknowledgement in `ConversationViewModel+Persistence.swift`.
  - **Stage session settings.** Keep pending next-turn model, effort, and permission changes runtime-scoped on `ConversationState`; stored thread fields can reflect the selected UI value immediately, but continuations must use the live session config until a new visible turn consumes the staged change.
  - **Drain resume cursors.** Fallback approval resumes must wait for all queued debounced saves, including follow-up saves, before resetting subscription tracking.
- Keep automatic session handoff terminal-aware:
  - **Mark pending from usage.** Context-window token rows may mark handoff pending before the provider turn is complete.
  - **Trigger on completion.** Start handoff only from a successful terminal token stop, keep queued messages behind pending handoff, and clear pending state on errors, interruptions, explicit stops, or handoff start.
- Keep live tool-approval decisions terminal-aware:
  - **Allow stays active.** Live approval can continue the provider turn, so leave `turnState` active until a terminal event arrives.
  - **Deny ends UI turn.** After a live denial decision is accepted, end the local turn even if Claude's trailing permission-denial token is delayed; later terminal tokens are still safe to process.
  - **Clear plan exits early.** A live `ExitPlanMode` approval should stop blocking the composer once the stream reports a non-plan permission mode or a successful matching tool result; do not wait for the final token while implementation is already streaming.
  - **Mirror live plan mode.** Runtime `permissionModeChanged` state is the source of truth for live permission decisions while a session is live; while next-turn settings are pending, fall back to the pre-change permission snapshot instead of the staged stored thread mode.
  - **Answer the newest prompt approval.** `AskUserQuestion` answers must resolve the newest unresolved same-prompt approval record before using stale in-memory approval state or falling back to normal Q/A sends.
  - **Dismiss prompts as interruptions.** `AskUserQuestion` dismissal should resolve the provider prompt as denied/cancelled, mark the prompt handled without a submitted-response card, end the active turn, and allow the centered `Interrupted` cue. Suppress only in-flight fallback events while the dismissal call is still resolving; do not keep durable prompt-dismiss state that can swallow later sends.
  - **Preserve fallback batches.** Fallback `tool_deferred` ends the local turn before delayed sibling approvals can arrive.
    Same-session same-family pending approvals should stay unresolved for batch resolution instead of being superseded only because `turnState.isActive` is false.
    Interleaved read-only tool results should not break same-family approval discovery; exclude approval rows only when their own tool result has arrived.
  - **Do not reopen completed approvals.** A matching tool result terminalizes unresolved approval rows, and late approval events for that tool ID must not recreate pending approval UI.

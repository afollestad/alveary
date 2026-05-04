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
- Keep automatic session handoff terminal-aware:
  - **Mark pending from usage.** Context-window token rows may mark handoff pending before the provider turn is complete.
  - **Trigger on completion.** Start handoff only from a successful terminal token stop, keep queued messages behind pending handoff, and clear pending state on errors, interruptions, explicit stops, or handoff start.
- Keep live tool-approval decisions terminal-aware:
  - **Allow stays active.** Live approval can continue the provider turn, so leave `turnState` active until a terminal event arrives.
  - **Deny ends UI turn.** After a live denial decision is accepted, end the local turn even if Claude's trailing permission-denial token is delayed; later terminal tokens are still safe to process.
  - **Clear plan exits early.** A live `ExitPlanMode` approval should stop blocking the composer once the stream reports a non-plan permission mode or a successful matching tool result; do not wait for the final token while implementation is already streaming.

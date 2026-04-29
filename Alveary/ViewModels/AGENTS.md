## View Models

These instructions apply to files under `Alveary/ViewModels/`.

- Keep view models as coordination layers: route UI intent, own observers/watchers, and delegate service-backed state to focused collaborators when state becomes shared or long-running.
- Put feature-specific view-model rules in the narrowest subfolder guidance, such as `Alveary/ViewModels/DiffViewer/AGENTS.md`.
- Keep `ConversationViewModel` companions focused by behavior:
  - **Route outbound work.** Put message sending, queued-message dispatch, and transport message construction in `ConversationViewModel+MessageDispatch.swift`.
  - **Handle inbound events.** Put provider event filtering, token stop handling, and synthetic event records in `ConversationViewModel+EventHandling.swift`.
  - **Record local user messages.** Put transcript-local user message insertion and auto-naming side effects in `ConversationViewModel+LocalMessages.swift`.
  - **Persist runtime state.** Put debounced SwiftData saves and runtime-buffer cursor acknowledgement in `ConversationViewModel+Persistence.swift`.

## Conversation View Models

These instructions apply to files directly under `Alveary/ViewModels/Conversation/` — `ConversationViewModel` itself, its subscription and event handling, setup and drafts, session settings, and transcript pull-request detection. Four scopes sit below: `ControllerRegistry/AGENTS.md` for lease ownership and thread status, `Approvals/AGENTS.md` for tool approvals and plan exits, `SessionHandoff/AGENTS.md` for the between-turn handoff, and `Outbound/AGENTS.md` for the send path.

**Keep a rule here only when the code that would violate it is not the code that documents it.** `ConversationViewModel+PullRequestDetection.swift` owns insert-time-only detection, the watermark's replay fence, why linking posts a notification instead of writing, and the filter-don't-delete rule for prompts.

### Companion Files

Keep `ConversationViewModel` companions focused by behavior:

- **Handle inbound events** — provider event filtering, token stop handling, synthetic records — in `ConversationViewModel+EventHandling.swift`. Main thread titles come from provider metadata there, not from the locally recorded rows in `Outbound/`.
- **Persist runtime state** — debounced SwiftData saves and runtime-buffer cursor acknowledgement — in `ConversationViewModel+Persistence.swift`.
- **Bound stream coalescing.** Live root-assistant chunk batching in `ConversationViewModel+Subscription.swift` uses count/size thresholds plus a short max-latency flush, so small deltas cannot sit buffered indefinitely and provider event order is preserved.
- **Recover stale provider sessions locally**, in `ConversationViewModel+NonresumableSession.swift`. If a stopped provider session cannot resume, start a fresh one for the same conversation and attach `Conversation.restoreContextFromHistory()` through staged transport context; sends, retries, and handoff must not fail only because provider-native history disappeared.

### Session Settings

- **Stage session settings.** Pending next-turn model, effort, speed, permission, and plan-mode changes stay runtime-scoped on `ConversationState`; stored thread fields may reflect the selected UI value immediately, but continuations use the live session config until a new visible turn consumes the staged change. `Approvals/AGENTS.md` owns the one exception.
- **Keep speed provider-scoped.** Route speed-mode UI through `applySpeedModeChange(_:supportsSpeedMode:)`; Fast is Codex-only until provider status reports support, and stale unsupported Fast normalizes to Standard before new sends.
- **Keep plan separate.** Route plan-mode UI through `applyPlanModeChange(_:)`; never encode plan as a permission dropdown value. Sync `runtimePlanModeEnabled` from runtime collaboration-mode events/status, including clearing it after successful `ExitPlanMode`.
- **`spawnPlanModeOverride` forces plan mode on while an `ExitPlanMode` approval is pending**, or the replayed tool is rejected with `You are not in plan mode.`

### Pull Request Detection

- **Hook every message insert site.** `scanInsertedMessageRecordForPullRequestLinks` runs from `Outbound/ConversationViewModel+LocalMessages.swift` and `ConversationViewModel+EventHandling.swift`, plus a rescan from `ConversationViewModel+Setup.swift` after draft materialization, which the draft gate skipped. A new insert path that does not call it silently stops detecting. `Alveary/ViewModels/PullRequests/Links/AGENTS.md` owns the link store this feeds, and `Alveary/Data/PullRequests/AGENTS.md` the watermark column.

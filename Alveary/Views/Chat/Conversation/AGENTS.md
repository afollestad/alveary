## Conversation View

These instructions cover `Alveary/Views/Chat/Conversation/` — `ConversationView`, its companions, and the usage summary it derives. The thread shell above it is `Alveary/Views/Chat/ThreadDetail/AGENTS.md`; `Alveary/ViewModels/Conversation/AGENTS.md` owns what `ConversationViewModel` does with the intent this view routes to it.

### Lifecycle

- **`ConversationView` activates its lease from `.task` and deactivates from `.onDisappear`.** Never construct a view-owned `ConversationViewModel` or start subscriptions from `init`.
- **Revalidate the selection after every `await` in project-derived async work.** Capture the request key or path before suspending and recheck it before updating provider state, cache entries, trust state, files, or diff routing, so draft project reassignment preserves conversation view identity.
- **App-shot trigger observation and capture routing are app-root work.** Keep only the debug transport-preview action here, and pair `ConversationState` mount tracking with view-lifecycle activation so a root-routed storage failure can choose between a visible `lastTurnError` and app-level feedback.

### Session Settings

`Alveary/ViewModels/Conversation/AGENTS.md` owns staging itself — which changes stage and what a continuation may consume; `Alveary/ViewModels/Conversation/Approvals/AGENTS.md` owns the approved-`ExitPlanMode` exception. These are the call-site rules.

- **`apply*Change` handlers stay on `ConversationViewModel` companions.** `ConversationView`'s `applyComposerReasoning*` methods only forward to them; do not inline the bodies back into the view, or they stop being testable against `MockAgentsManager` (`ConversationViewModelTests+Settings.swift`).
- **Call a handler directly from `Picker` `set:` — no outer `Task { await ... }`.** Its synchronous prologue must run on the click's own cycle; an outer `Task` defers a MainActor cycle and briefly paints the stale selection.
- **Use the right write gate.** Model, effort, and permission use `canApplySettingsChange`; provider and worktree are pre-startup only. Send-in-flight, setup, handoff steering, reconfiguration, and project-trust blocks reject writes either way.
- **Gate the fork on `shouldReconfigureOnSettingChange()`, never `agentsManager.isRunning(conversationId:)`.** Claude's `-p --input-format stream-json` process can exit between turns, so `isRunning` silently drops the fork; `reconfigureSession` already handles a dead process.
- **Do not add a `!isReconfiguringSession` check at the handler layer.** `reconfigureSession` already returns `.nextTurnRequired` on a concurrent attempt, and `.progressOnly(.reconfiguringSession)` disables the pickers meanwhile.
- **Derive the context-window summary in `ConversationUsageSummary`, not in composer controls**, passing provider and accounting context so Codex cached-input and Claude cache-read rows count.

### Transcript Data Flow

- **Keep transcript updates incremental while a turn is active.** Persisted live-turn events append directly into `ChatItemGrouper`; full regrouping from the `events` query waits for the turn to end, so the active turn cannot starve composer interactions like autocomplete or text insertion.
- **Fetch current records through `ConversationViewModel` at mount and regrouping boundaries.** A SwiftUI `@Query` snapshot can lag records inserted by background services such as scheduled-task materialization.
- **Fall back to that snapshot only on mount and non-forced refreshes**, and only when it is not older than the current grouper. A forced turn-end refresh never falls back; a failed fetch there preserves the current grouper.

## Chat View Details

These instructions cover chat-specific view code under `Alveary/Views/Chat/`.

- Conversation rename in multi-conversation tabs is inline via `editingConversationID` in `ConversationTabChip`, not a separate modal flow.
- Transcript auto-follow should stay pinned when the user is already at the bottom and new content increases transcript height, including wrapped streaming-bubble growth. Treat content-size growth differently from a user-initiated scroll-away so the `Jump to bottom` affordance only appears after the user actually leaves the bottom.
- In `ChatTranscriptView`, keep the bottom inset inside the `chat-bottom` scroll target instead of as trailing stack padding. Bottom padding after the anchor leaves a small extra scroll range when entering a thread or jumping to the bottom.
- Transcript follow mode should also survive transcript viewport-height changes caused by bottom-area composer banners or strips appearing and disappearing. If the user did not scroll and they were already near bottom, treat container-height changes like other bottom-pinned layout changes and keep the transcript anchored.
- Composer top separators that appear while the transcript is scrolled up should live in the composer panel's background layer, not a parent overlay, so autocomplete popups can cover them without the separator bleeding through.
- `ThreadDetailConversationTabs` should keep the system `.bar` background for the header chrome and add any custom separator as an overlay. Replacing the bar with `windowBackgroundColor` creates an unintended dark strip in the live app.
- Conversation tab chips are not list rows, but they should mirror the same press-feedback principles: let the select action own the full capsule hit area, overlay trailing affordances like the close button on top of that surface, and prefer fill changes over capsule strokes for selected styling because macOS can render stray vertical artifacts from chip outlines in snapshots.
- `EmptyThreadState` checks `isCancellingInitialSetup` before `setupPhase` so cancellation feedback takes precedence even when `setupPhase` is still set mid-rollback. Keep that ordering if you restructure the view; otherwise the empty-thread pane will flicker back to "Creating worktree" during the rollback shell commands.

## Interaction Contracts

These capture conversation-view interaction patterns. Keep new UI aligned with them unless you are intentionally redesigning the behavior across the app.

- Session reconfiguration is a between-turn action. Do not let agent/session setting changes reconfigure a conversation while a turn is active or a send is still in flight; those changes must wait until the current turn finishes.
- Queued messages stay stacked above the chat composer until they are actually sent. Do not render pending queued entries in the transcript as if they were already part of the conversation history.
- Once a queued message is actually attempted, it belongs to the transcript. If that attempted send fails, show retry affordances on the transcript user message rather than moving it back into the queued-message list.
- User-requested turn cancellation is an interruption, not a generic failure. Stopped turns should clear composer error banners, render a centered `Interrupted` transcript note, and persist a `stop` session note so restore/archive context does not summarize the turn as an error.
- User-requested cancellation of initial-setup (worktree creation + agent spawn for a new thread) is a reset, not a failure. `ConversationViewModel.cancel()` must cancel the tracked `initialSetupTask` and flip `state.isCancellingInitialSetup = true` so the composer shows a spinner instead of the stop button; the existing `rollbackFailedInitialSetup` path restores the draft and clears `hasCompletedInitialSetup`, and `sendDraft` / `retryDraft` must swallow `CancellationError` so no error banner appears. A subsequent send re-enters setup via the normal `needsSetup` check.
- While a turn is active, keep transcript updates incremental. Persisted live-turn events should append directly into `ChatItemGrouper`, and full transcript regrouping from the `events` query should be deferred until the turn ends so the active turn does not starve composer interactions like autocomplete or text insertion.
- Live root-assistant `messageChunk` events should be coalesced before they hop onto the main actor. Do not process every streamed text delta as its own `MainActor` mutation, or active turns can starve transcript completion and composer interactions.
- `ConversationViewModel` agent subscriptions are view-lifecycle owned, not initializer-owned. Keep `activateViewLifecycle()` / `deactivateViewLifecycle()` wired from `ConversationView`'s `.task` and `.onDisappear` instead of restarting subscriptions from `init`, because parent SwiftUI refreshes can recreate the model and churn `activeSubscriptionToken`.
